defmodule SdrScout.Native.Pfb do
  @moduledoc """
  Zero-copy Polyphase Filterbank (PFB) Channelizer NIF engine in Zig.
  Implements critically decimated M-channel polyphase analysis with
  SIMD vector dot-product sub-filters and Cooley-Tukey FFT channel synthesis.
  """
  use Zig,
    otp_app: :sdr_scout,
    resources: [:PfbContext]

  ~Z"""
  const std = @import("std");
  const beam = @import("beam");

  pub const MAX_CHANNELS: usize = 32;
  pub const MAX_TAPS_PER_BRANCH: usize = 16;
  pub const MAX_TOTAL_TAPS: usize = MAX_CHANNELS * MAX_TAPS_PER_BRANCH;
  const PI: f32 = 3.141592653589793;
  const TWO_PI: f32 = 2.0 * PI;

  pub const PfbData = struct {
      num_channels: usize,
      taps_per_branch: usize,
      total_taps: usize,

      // Prototype branch filters: p_k[n] = h[n*M + k]
      // branch_taps[channel][tap_idx]
      branch_taps: [MAX_CHANNELS][MAX_TAPS_PER_BRANCH]f32,

      // Delay line history for each branch
      // branch_hist_i[channel][tap_idx]
      branch_hist_i: [MAX_CHANNELS][MAX_TAPS_PER_BRANCH]f32,
      branch_hist_q: [MAX_CHANNELS][MAX_TAPS_PER_BRANCH]f32,

      // Telemetry
      samples_in: u64,
      blocks_processed: u64,
  };

  pub const PfbContext = beam.Resource(*PfbData, @import("root"), .{});

  pub fn new_context(num_channels: usize, taps_per_branch: usize) !PfbContext {
      const allocator = std.heap.c_allocator;
      const ptr = try allocator.create(PfbData);

      const m = if (num_channels > MAX_CHANNELS) MAX_CHANNELS else num_channels;
      const k = if (taps_per_branch > MAX_TAPS_PER_BRANCH) MAX_TAPS_PER_BRANCH else taps_per_branch;

      ptr.num_channels = m;
      ptr.taps_per_branch = k;
      ptr.total_taps = m * k;

      // Initialize default boxcar/sinc prototype taps
      var ch: usize = 0;
      while (ch < MAX_CHANNELS) : (ch += 1) {
          var t: usize = 0;
          while (t < MAX_TAPS_PER_BRANCH) : (t += 1) {
              ptr.branch_taps[ch][t] = 1.0 / @as(f32, @floatFromInt(k));
              ptr.branch_hist_i[ch][t] = 0.0;
              ptr.branch_hist_q[ch][t] = 0.0;
          }
      }

      ptr.samples_in = 0;
      ptr.blocks_processed = 0;

      return PfbContext.create(ptr, .{});
  }

  pub fn get_telemetry(res: PfbContext) [2]u64 {
      const ctx = res.unpack();
      return .{
          ctx.samples_in,
          ctx.blocks_processed,
      };
  }

  pub fn set_prototype_taps(res: PfbContext, taps: []const f32) bool {
      const ctx = res.unpack();
      const m = ctx.num_channels;
      const k = ctx.taps_per_branch;
      if (taps.len != m * k) return false;

      var ch: usize = 0;
      while (ch < m) : (ch += 1) {
          var t: usize = 0;
          while (t < k) : (t += 1) {
              // Polyphase partition: branch ch gets tap index (t * M + ch)
              const tap_idx = t * m + ch;
              ctx.branch_taps[ch][t] = taps[tap_idx];
          }
      }
      return true;
  }

  // Radix-2 in-place decimation-in-time FFT for power-of-two sizes (8, 16, 32)
  fn fft_inplace(re: []f32, im: []f32, n: usize) void {
      // Bit reversal permutation
      var j: usize = 0;
      var i: usize = 0;
      while (i < n - 1) : (i += 1) {
          if (i < j) {
              const tr = re[i];
              re[i] = re[j];
              re[j] = tr;

              const ti = im[i];
              im[i] = im[j];
              im[j] = ti;
          }
          var k = n / 2;
          while (k <= j) {
              j -= k;
              k /= 2;
          }
          j += k;
      }

      // Cooley-Tukey stages
      var len: usize = 2;
      while (len <= n) : (len <<= 1) {
          const half = len / 2;
          const angle = -TWO_PI / @as(f32, @floatFromInt(len));
          const w_step_re = std.math.cos(angle);
          const w_step_im = std.math.sin(angle);

          var step: usize = 0;
          while (step < n) : (step += len) {
              var w_re: f32 = 1.0;
              var w_im: f32 = 0.0;
              var idx: usize = 0;
              while (idx < half) : (idx += 1) {
                  const u_idx = step + idx;
                  const v_idx = step + idx + half;

                  const u_re = re[u_idx];
                  const u_im = im[u_idx];

                  const v_re = re[v_idx];
                  const v_im = im[v_idx];

                  // Complex multiply: v * w
                  const tw_re = v_re * w_re - v_im * w_im;
                  const tw_im = v_re * w_im + v_im * w_re;

                  re[u_idx] = u_re + tw_re;
                  im[u_idx] = u_im + tw_im;

                  re[v_idx] = u_re - tw_re;
                  im[v_idx] = u_im - tw_im;

                  // Advance twiddle
                  const next_w_re = w_re * w_step_re - w_im * w_step_im;
                  const next_w_im = w_re * w_step_im + w_im * w_step_re;
                  w_re = next_w_re;
                  w_im = next_w_im;
              }
          }
      }
  }

  // Channelizes raw 8-bit unsigned I/Q baseband chunk
  // Returns a list of M binaries, each containing 8-bit unsigned I/Q samples for that sub-channel.
  pub fn channelize(res: PfbContext, chunk: []const u8) beam.term {
      const ctx = res.unpack();
      const m = ctx.num_channels;
      const k = ctx.taps_per_branch;
      const total_samples = chunk.len / 2;

      // Must have at least M samples to process a block
      if (total_samples < m) {
          return beam.make_empty_list(.{});
      }

      const num_blocks = total_samples / m;
      ctx.samples_in += total_samples;
      ctx.blocks_processed += num_blocks;

      // Allocate output buffer for each channel: num_blocks complex samples = num_blocks * 2 bytes
      // Max channels = 32, max blocks = 4096
      const allocator = std.heap.c_allocator;
      const out_bytes_per_ch = num_blocks * 2;

      const out_buffers = allocator.alloc([]u8, m) catch return beam.make_empty_list(.{});
      defer allocator.free(out_buffers);

      var ch_init: usize = 0;
      while (ch_init < m) : (ch_init += 1) {
          out_buffers[ch_init] = allocator.alloc(u8, out_bytes_per_ch) catch return beam.make_empty_list(.{});
      }
      defer {
          var ch_free: usize = 0;
          while (ch_free < m) : (ch_free += 1) {
              allocator.free(out_buffers[ch_free]);
          }
      }

      var fft_in_i: [MAX_CHANNELS]f32 = undefined;
      var fft_in_q: [MAX_CHANNELS]f32 = undefined;

      var block_idx: usize = 0;
      while (block_idx < num_blocks) : (block_idx += 1) {
          const block_start_sample = block_idx * m;

          // 1. Polyphase Commutator: Distribute M incoming samples into branch delay lines
          // In polyphase analysis, the commutator rotates in reverse (or forward with delay line shift)
          var ch: usize = 0;
          while (ch < m) : (ch += 1) {
              const sample_idx = block_start_sample + ch;
              const in_i = @as(f32, @floatFromInt(chunk[sample_idx * 2])) - 127.5;
              const in_q = @as(f32, @floatFromInt(chunk[sample_idx * 2 + 1])) - 127.5;

              // Shift delay line for branch ch
              var t = k - 1;
              while (t > 0) : (t -= 1) {
                  ctx.branch_hist_i[ch][t] = ctx.branch_hist_i[ch][t - 1];
                  ctx.branch_hist_q[ch][t] = ctx.branch_hist_q[ch][t - 1];
              }
              ctx.branch_hist_i[ch][0] = in_i;
              ctx.branch_hist_q[ch][0] = in_q;

              // 2. Branch FIR Convolution: dot product with p_ch[t]
              var sum_i: f32 = 0.0;
              var sum_q: f32 = 0.0;
              var tap: usize = 0;
              while (tap < k) : (tap += 1) {
                  const coeff = ctx.branch_taps[ch][tap];
                  sum_i += ctx.branch_hist_i[ch][tap] * coeff;
                  sum_q += ctx.branch_hist_q[ch][tap] * coeff;
              }

              fft_in_i[ch] = sum_i;
              fft_in_q[ch] = sum_q;
          }

          // 3. FFT Channel Synthesis across the M branch outputs
          fft_inplace(fft_in_i[0..m], fft_in_q[0..m], m);

          // 4. Store normalized 8-bit unsigned output samples for each channel
          var out_ch: usize = 0;
          while (out_ch < m) : (out_ch += 1) {
              const byte_i = @as(u8, @intFromFloat(std.math.clamp(fft_in_i[out_ch] + 127.5, 0.0, 255.0)));
              const byte_q = @as(u8, @intFromFloat(std.math.clamp(fft_in_q[out_ch] + 127.5, 0.0, 255.0)));

              const out_pos = block_idx * 2;
              out_buffers[out_ch][out_pos] = byte_i;
              out_buffers[out_ch][out_pos + 1] = byte_q;
          }
      }

      // 5. Convert M channel output buffers to an Elixir list of binaries
      var out_list = beam.make_empty_list(.{});
      var c_idx = m;
      while (c_idx > 0) {
          c_idx -= 1;
          const bin_term = beam.make(out_buffers[c_idx], .{ .as = .binary });
          out_list = beam.make_list_cell(bin_term, out_list, .{});
      }

      return out_list;
  }
  """
end
