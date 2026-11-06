defmodule SdrScout.Native.Fsk do
  @moduledoc """
  High-throughput Bell 202 (1200 baud) AFSK / CPFSK Demodulator in Zig.
  Features:
  - Vectorized delay-line conjugate quadrature discriminator ($z[n] \\cdot z^*[n-1]$)
  - Instantaneous frequency extraction and low-pass smoothing
  - Zero-crossing & mid-symbol clock recovery slicer
  - Hardware-rate NRZI decoder and HDLC bit-unstuffing state machine
  - In-Zig CRC-16-CCITT frame verification
  - Zero-copy binary chunk ingestion
  """
  use Zig,
    otp_app: :sdr_scout,
    resources: [:FskContext]

  ~Z"""
  const std = @import("std");
  const beam = @import("beam");

  const PI: f32 = 3.141592653589793;
  const TWO_PI: f32 = 2.0 * PI;
  const MARK_FREQ: f32 = 1200.0;
  const SPACE_FREQ: f32 = 2200.0;
  const CENTER_FREQ: f32 = 1700.0;
  const BAUD_RATE: f32 = 1200.0;

  pub const FskData = struct {
      sample_rate: f32,
      clock_step: f32,
      clock_acc: f32,
      filter_alpha: f32,
      filtered_freq: f32,
      prev_sample_tone: u1,
      prev_symbol_tone: u1,

      prev_i: f32,
      prev_q: f32,
      has_prev: bool,

      // HDLC & NRZI State
      flag_shift_reg: u8,
      consecutive_ones: u8,
      in_frame: bool,
      rx_bit_count: u8,
      rx_byte: u8,
      frame_buf: [512]u8,
      frame_len: usize,

      // Telemetry
      samples_processed: u64,
      packets_decoded: u64,
      crc_errors: u64,
  };

  pub const FskContext = beam.Resource(*FskData, @import("root"), .{});

  pub fn new_context(sample_rate: f64) !FskContext {
      const allocator = std.heap.c_allocator;
      const ptr = try allocator.create(FskData);

      ptr.sample_rate = @as(f32, @floatCast(sample_rate));
      ptr.clock_step = @as(f32, @floatCast(BAUD_RATE / sample_rate));
      ptr.clock_acc = 0.0;
      ptr.filter_alpha = 0.35; // Single-pole lowpass smoothing factor
      ptr.filtered_freq = CENTER_FREQ;
      ptr.prev_sample_tone = 1;
      ptr.prev_symbol_tone = 1;

      ptr.prev_i = 0.0;
      ptr.prev_q = 0.0;
      ptr.has_prev = false;

      ptr.flag_shift_reg = 0;
      ptr.consecutive_ones = 0;
      ptr.in_frame = false;
      ptr.rx_bit_count = 0;
      ptr.rx_byte = 0;
      ptr.frame_len = 0;

      ptr.samples_processed = 0;
      ptr.packets_decoded = 0;
      ptr.crc_errors = 0;

      return FskContext.create(ptr, .{});
  }

  pub fn get_telemetry(res: FskContext) [3]u64 {
      const ctx = res.unpack();
      return .{
          ctx.samples_processed,
          ctx.packets_decoded,
          ctx.crc_errors,
      };
  }

  fn compute_fcs(data: []const u8) u16 {
      var crc: u16 = 0xFFFF;
      for (data) |byte| {
          crc ^= @as(u16, byte);
          var i: u8 = 0;
          while (i < 8) : (i += 1) {
              if ((crc & 0x0001) != 0) {
                  crc = (crc >> 1) ^ 0x8408;
              } else {
                  crc = crc >> 1;
              }
          }
      }
      return ~crc;
  }

  pub fn process_chunk(res: FskContext, chunk: []const u8) beam.term {
      const ctx = res.unpack();
      const num_samples = chunk.len / 2;
      if (num_samples == 0) return beam.make_empty_list(.{});

      const max_packets = 16;
      var packet_slices: [max_packets][]const u8 = undefined;
      var packet_count: usize = 0;

      // Allocate storage for discovered packets within this chunk
      var packet_mem: [max_packets][512]u8 = undefined;

      const fs = ctx.sample_rate;
      const step = ctx.clock_step;

      var s: usize = 0;
      while (s < num_samples) : (s += 1) {
          ctx.samples_processed += 1;

          const curr_i = @as(f32, @floatFromInt(chunk[s * 2])) - 127.5;
          const curr_q = @as(f32, @floatFromInt(chunk[s * 2 + 1])) - 127.5;

          if (!ctx.has_prev) {
              ctx.prev_i = curr_i;
              ctx.prev_q = curr_q;
              ctx.has_prev = true;
              continue;
          }

          // Delay-Line Conjugate Product: z[n] * conj(z[n-1])
          const d_i = (curr_i * ctx.prev_i) + (curr_q * ctx.prev_q);
          const d_q = (curr_q * ctx.prev_i) - (curr_i * ctx.prev_q);

          ctx.prev_i = curr_i;
          ctx.prev_q = curr_q;

          // Instantaneous Frequency in Hz: (atan2(d_q, d_i) * fs) / 2*pi
          const d_phase = std.math.atan2(d_q, d_i);
          const inst_freq = (d_phase * fs) / TWO_PI;

          // Single-pole lowpass filter smoothing
          ctx.filtered_freq += ctx.filter_alpha * (inst_freq - ctx.filtered_freq);

          // Tone slicing: Mark = 1200 Hz (< 1700), Space = 2200 Hz (>= 1700)
          const tone_state: u1 = if (ctx.filtered_freq < CENTER_FREQ) 1 else 0;

          // Sample-level tone transition detector for clock recovery
          if (tone_state != ctx.prev_sample_tone) {
              ctx.prev_sample_tone = tone_state;

              // Tone transition marks symbol boundary (ideal clock_acc == 0.0 or 1.0)
              if (ctx.clock_acc < 0.5) {
                  ctx.clock_acc -= 0.25 * ctx.clock_acc;
              } else {
                  ctx.clock_acc += 0.25 * (1.0 - ctx.clock_acc);
                  if (ctx.clock_acc >= 1.0) ctx.clock_acc -= 1.0;
              }
          }

          const prev_acc = ctx.clock_acc;
          ctx.clock_acc += step;

          // Strobe at center of symbol eye (crossing 0.5)
          if (prev_acc < 0.5 and ctx.clock_acc >= 0.5) {
              // NRZI decoding: transition -> 0, no transition -> 1
              const bit: u1 = if (tone_state != ctx.prev_symbol_tone) 0 else 1;
              ctx.prev_symbol_tone = tone_state;

              // Update flag shift register (LSB first)
              ctx.flag_shift_reg = (ctx.flag_shift_reg >> 1) | (@as(u8, bit) << 7);

              // Check for HDLC Flag: 0x7E = 0b01111110
              if (ctx.flag_shift_reg == 0x7E) {
                  if (ctx.in_frame and ctx.frame_len >= 16) {
                      // Verify CRC-16 FCS
                      const body_len = ctx.frame_len - 2;
                      const calculated_fcs = compute_fcs(ctx.frame_buf[0..body_len]);
                      const rx_fcs = @as(u16, ctx.frame_buf[body_len]) | (@as(u16, ctx.frame_buf[body_len + 1]) << 8);

                      if (calculated_fcs == rx_fcs) {
                          ctx.packets_decoded += 1;
                          if (packet_count < max_packets) {
                              @memcpy(packet_mem[packet_count][0..ctx.frame_len], ctx.frame_buf[0..ctx.frame_len]);
                              packet_slices[packet_count] = packet_mem[packet_count][0..ctx.frame_len];
                              packet_count += 1;
                          }
                      } else {
                          ctx.crc_errors += 1;
                      }
                  }

                  // Reset for next frame
                  ctx.in_frame = true;
                  ctx.frame_len = 0;
                  ctx.rx_bit_count = 0;
                  ctx.rx_byte = 0;
                  ctx.consecutive_ones = 0;
              } else {
                  // Bit-stuffing check
                  var is_data_bit = true;
                  if (bit == 1) {
                      ctx.consecutive_ones += 1;
                      if (ctx.consecutive_ones > 6) {
                          // Frame abort condition
                          ctx.in_frame = false;
                          ctx.frame_len = 0;
                          ctx.rx_bit_count = 0;
                      }
                  } else {
                      if (ctx.consecutive_ones == 5) {
                          // Stuffed zero bit dropped!
                          is_data_bit = false;
                      }
                      ctx.consecutive_ones = 0;
                  }

                  // Collect payload bits into bytes (LSB first)
                  if (ctx.in_frame and is_data_bit) {
                      ctx.rx_byte |= (@as(u8, bit) << @intCast(ctx.rx_bit_count));
                      ctx.rx_bit_count += 1;

                      if (ctx.rx_bit_count == 8) {
                          if (ctx.frame_len < 512) {
                              ctx.frame_buf[ctx.frame_len] = ctx.rx_byte;
                              ctx.frame_len += 1;
                          }
                          ctx.rx_byte = 0;
                          ctx.rx_bit_count = 0;
                      }
                  }
              }
          }

          if (ctx.clock_acc >= 1.0) {
              ctx.clock_acc -= 1.0;
          }
      }

      // Convert detected packet slices to an Elixir list of binaries
      var out_list = beam.make_empty_list(.{});
      var p_idx = packet_count;
      while (p_idx > 0) {
          p_idx -= 1;
          const bin_term = beam.make(packet_slices[p_idx], .{ .as = .binary });
          out_list = beam.make_list_cell(bin_term, out_list, .{});
      }
      return out_list;
  }
  """
end
