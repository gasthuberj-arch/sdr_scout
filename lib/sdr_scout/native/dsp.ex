defmodule SdrScout.Native.Dsp do
  @moduledoc """
  High-throughput stateful DSP engine in Zig.
  Features:
  - Stateful Zig Resource holding a 240-sample (480-byte) overlap buffer
  - SIMD-accelerated linear magnitude: @Vector(16, f32) with @sqrt
  - 16-sample preamble correlator (8 µs pulse pattern)
  - 112-bit (224-sample) PPM bit slicer
  - In-Zig CRC-24 verification and 1-bit syndrome error recovery
  - Live DSP telemetry metrics
  """
  use Zig, otp_app: :sdr_scout

  ~Z"""
  const std = @import("std");
  const beam = @import("beam");

  // Mode-S CRC-24 generator polynomial: 0x1FFF409
  const CRC24_POLY: u32 = 0x1FFF409;

  // Precomputed syndrome table for single-bit flips in 112-bit frames
  // bit 0 = MSB (frame[0] & 0x80), bit 111 = LSB (frame[13] & 0x01)
  var SYNDROME_TABLE: [112]u32 = undefined;
  var SYNDROMES_INITIALIZED: bool = false;

  fn init_syndromes() void {
      if (SYNDROMES_INITIALIZED) return;
      var bit: usize = 0;
      while (bit < 112) : (bit += 1) {
          var frame = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
          frame[bit / 8] |= @as(u8, 1) << @intCast(7 - (bit % 8));
          SYNDROME_TABLE[bit] = compute_crc24(&frame);
      }
      SYNDROMES_INITIALIZED = true;
  }

  fn compute_crc24(frame: []const u8) u32 {
      var rem: u32 = 0;
      for (frame) |byte| {
          var b: u32 = 0x80;
          while (b > 0) : (b >>= 1) {
              const bit: u32 = if ((byte & b) != 0) 1 else 0;
              const msb: u32 = (rem >> 23) & 1;
              rem = ((rem << 1) & 0xFFFFFF) | bit;
              if (msb == 1) {
                  rem ^= CRC24_POLY;
              }
          }
      }
      return rem & 0xFFFFFF;
  }

  // 16-sample standard preamble filter
  // Pulses at: 0, 2, 7, 9
  // Quiet at:  1, 3, 4, 5, 6, 8, 10, 11, 12, 13, 14, 15
  fn is_preamble(mag: []const f32, idx: usize) bool {
      if (idx + 16 > mag.len) return false;

      const p0 = mag[idx + 0];
      const p1 = mag[idx + 2];
      const p2 = mag[idx + 7];
      const p3 = mag[idx + 9];

      // Pulse high average
      const pulse_avg = (p0 + p1 + p2 + p3) / 4.0;
      if (pulse_avg < 30.0) return false;

      // Check quiet samples
      const q0 = mag[idx + 1];
      const q1 = mag[idx + 3];
      const q2 = mag[idx + 4];
      const q3 = mag[idx + 5];
      const q4 = mag[idx + 6];
      const q5 = mag[idx + 8];
      const q6 = mag[idx + 10];
      const q7 = mag[idx + 11];
      const q8 = mag[idx + 12];
      const q9 = mag[idx + 13];
      const q10 = mag[idx + 14];
      const q11 = mag[idx + 15];

      const quiet_avg = (q0 + q1 + q2 + q3 + q4 + q5 + q6 + q7 + q8 + q9 + q10 + q11) / 12.0;

      // Preamble requires pulse average to be significantly above quiet noise floor
      // and each of the 4 pulse positions must exceed quiet average
      if (pulse_avg < quiet_avg * 1.8) return false;
      if (p0 < quiet_avg or p1 < quiet_avg or p2 < quiet_avg or p3 < quiet_avg) return false;

      return true;
  }

  // Slice 112 PPM bits (224 samples) into 14 bytes
  fn slice_ppm(mag: []const f32, start_sample: usize, out_frame: *[14]u8) void {
      var bit_idx: usize = 0;
      while (bit_idx < 112) : (bit_idx += 1) {
          const s0 = mag[start_sample + bit_idx * 2];
          const s1 = mag[start_sample + bit_idx * 2 + 1];

          const byte_idx = bit_idx / 8;
          const bit_pos = 7 - (bit_idx % 8);

          if (s0 > s1) {
              out_frame[byte_idx] |= (@as(u8, 1) << @intCast(bit_pos));
          } else {
              out_frame[byte_idx] &= ~(@as(u8, 1) << @intCast(bit_pos));
          }
      }
  }

  // Stateful DSP Resource
  pub const DspContext = struct {
      overlap_buf: [480]u8,
      overlap_len: usize,
      samples_processed: u64,
      preambles_detected: u64,
      crc_valid: u64,
      single_bit_recovered: u64,

      pub fn init() DspContext {
          init_syndromes();
          var ctx = DspContext{
              .overlap_buf = undefined,
              .overlap_len = 0,
              .samples_processed = 0,
              .preambles_detected = 0,
              .crc_valid = 0,
              .single_bit_recovered = 0,
          };
          @memset(&ctx.overlap_buf, 127);
          return ctx;
      }
  };

  pub fn new_context() DspContext {
      return DspContext.init();
  }

  pub fn get_telemetry(ctx: *DspContext) [4]u64 {
      return .{
          ctx.samples_processed,
          ctx.preambles_detected,
          ctx.crc_valid,
          ctx.single_bit_recovered,
      };
  }

  // Process incoming chunk of raw I/Q bytes
  // Prepend overlap tail, compute SIMD magnitude, scan preambles,
  // slice PPM, check & fix CRC-24, and emit 14-byte frames.
  pub fn process_chunk(ctx: *DspContext, chunk: []const u8) beam.term {
      init_syndromes();

      // Allocate total stream buffer = overlap + chunk
      const total_bytes = ctx.overlap_len + chunk.len;
      if (total_bytes < 480) {
          // Store in overlap buffer and return empty list
          @memcpy(ctx.overlap_buf[ctx.overlap_len .. ctx.overlap_len + chunk.len], chunk);
          ctx.overlap_len += chunk.len;
          return beam.make_empty_list(.{});
      }

      var gpa = std.heap.GeneralPurposeAllocator(.{}){};
      defer _ = gpa.deinit();
      const allocator = gpa.allocator();

      const iq_buf = allocator.alloc(u8, total_bytes) catch return beam.make_empty_list(.{});
      defer allocator.free(iq_buf);

      @memcpy(iq_buf[0..ctx.overlap_len], ctx.overlap_buf[0..ctx.overlap_len]);
      @memcpy(iq_buf[ctx.overlap_len..total_bytes], chunk);

      // Save trailing 480 bytes for next chunk
      const save_start = if (total_bytes >= 480) total_bytes - 480 else 0;
      const save_len = total_bytes - save_start;
      @memcpy(ctx.overlap_buf[0..save_len], iq_buf[save_start..total_bytes]);
      ctx.overlap_len = save_len;

      const num_samples = total_bytes / 2;
      ctx.samples_processed += num_samples;

      const mag_buf = allocator.alloc(f32, num_samples) catch return beam.make_empty_list(.{});
      defer allocator.free(mag_buf);

      // Vectorized SIMD Linear Magnitude using @Vector(16, f32) and @sqrt
      const simd_lanes = 16;
      var s_idx: usize = 0;
      const simd_limit = if (num_samples >= simd_lanes) num_samples - simd_lanes else 0;

      while (s_idx <= simd_limit and num_samples >= simd_lanes) : (s_idx += simd_lanes) {
          var i_vec: @Vector(simd_lanes, f32) = undefined;
          var q_vec: @Vector(simd_lanes, f32) = undefined;

          inline for (0..simd_lanes) |lane| {
              const byte_pos = (s_idx + lane) * 2;
              i_vec[lane] = @as(f32, @floatFromInt(iq_buf[byte_pos])) - 127.5;
              q_vec[lane] = @as(f32, @floatFromInt(iq_buf[byte_pos + 1])) - 127.5;
          }

          const mag2 = i_vec * i_vec + q_vec * q_vec;
          const mag = @sqrt(mag2);

          inline for (0..simd_lanes) |lane| {
              mag_buf[s_idx + lane] = mag[lane];
          }
      }

      // Scalar tail for remainder
      while (s_idx < num_samples) : (s_idx += 1) {
          const byte_pos = s_idx * 2;
          const i_f = @as(f32, @floatFromInt(iq_buf[byte_pos])) - 127.5;
          const q_f = @as(f32, @floatFromInt(iq_buf[byte_pos + 1])) - 127.5;
          mag_buf[s_idx] = @sqrt(i_f * i_f + q_f * q_f);
      }

      // Preamble scanning and frame extraction
      var frames = std.ArrayList([14]u8).init(allocator);
      defer frames.deinit();

      var sample_idx: usize = 0;
      const search_limit = if (num_samples >= 240) num_samples - 240 else 0;

      while (sample_idx < search_limit) {
          if (is_preamble(mag_buf, sample_idx)) {
              ctx.preambles_detected += 1;
              var candidate_frame: [14]u8 = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
              slice_ppm(mag_buf, sample_idx + 16, &candidate_frame);

              // Check CRC-24
              const syndrome = compute_crc24(&candidate_frame);
              if (syndrome == 0) {
                  ctx.crc_valid += 1;
                  frames.append(candidate_frame) catch {};
                  sample_idx += 240; // Skip past the message duration
                  continue;
              } else {
                  // Attempt 1-bit syndrome error recovery
                  var bit_pos: usize = 0;
                  var recovered = false;
                  while (bit_pos < 112) : (bit_pos += 1) {
                      if (SYNDROME_TABLE[bit_pos] == syndrome) {
                          // Found the exact corrupted bit: flip it
                          candidate_frame[bit_pos / 8] ^= (@as(u8, 1) << @intCast(7 - (bit_pos % 8)));
                          ctx.single_bit_recovered += 1;
                          frames.append(candidate_frame) catch {};
                          recovered = true;
                          break;
                      }
                  }
                  if (recovered) {
                      sample_idx += 240;
                      continue;
                  }
              }
          }
          sample_idx += 1;
      }

      // Build return list of binaries for Elixir
      var out_list = beam.make_empty_list(.{});
      var f_idx = frames.items.len;
      while (f_idx > 0) {
          f_idx -= 1;
          const bin_term = beam.make(frames.items[f_idx][0..14], .{ .as = .binary });
          out_list = beam.make_list_cell(bin_term, out_list, .{});
      }

      return out_list;
  }
  """
end
