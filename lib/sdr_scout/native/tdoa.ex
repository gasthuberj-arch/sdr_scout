defmodule SdrScout.Native.Tdoa do
  @moduledoc """
  High-precision Time Difference of Arrival (TDOA) Cross-Correlation in Zig.
  Features:
  - Generalized Cross-Correlation with Phase Transform (GCC-PHAT)
  - Radix-2 FFT / IFFT spectral analysis
  - 3-point sub-sample parabolic interpolation for nanosecond delay resolution
  - Vectorized complex cross-spectral density estimation
  """
  use Zig,
    otp_app: :sdr_scout

  ~Z"""
  const std = @import("std");
  const beam = @import("beam");

  const PI: f32 = 3.141592653589793;
  const TWO_PI: f32 = 2.0 * PI;

  // In-place Radix-2 FFT / IFFT
  fn fft_radix2(re: []f32, im: []f32, n: usize, inverse: bool) void {
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

      // Cooley-Tukey butterfly stages
      var len: usize = 2;
      while (len <= n) : (len <<= 1) {
          const half = len / 2;
          const sign: f32 = if (inverse) 1.0 else -1.0;
          const angle = sign * TWO_PI / @as(f32, @floatFromInt(len));
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

                  const next_w_re = w_re * w_step_re - w_im * w_step_im;
                  const next_w_im = w_re * w_step_im + w_im * w_step_re;
                  w_re = next_w_re;
                  w_im = next_w_im;
              }
          }
      }

      if (inverse) {
          const inv_n = 1.0 / @as(f32, @floatFromInt(n));
          var k_idx: usize = 0;
          while (k_idx < n) : (k_idx += 1) {
              re[k_idx] *= inv_n;
              im[k_idx] *= inv_n;
          }
      }
  }

  // Estimates fractional time delay between two signals using GCC-PHAT
  // Inputs:
  // - s1_bytes: interleaved 8-bit unsigned I/Q samples of channel 1
  // - s2_bytes: interleaved 8-bit unsigned I/Q samples of channel 2
  // - fft_size: FFT size (must be power of 2, e.g. 512, 1024, 2048)
  // Returns: [2]f32: { fractional_lag_samples, peak_correlation_magnitude }
  pub fn gcc_phat_delay(s1_bytes: []const u8, s2_bytes: []const u8, fft_size: usize) [2]f32 {
      const num_samples = @min(s1_bytes.len / 2, s2_bytes.len / 2);
      const n = if (fft_size > 0 and (fft_size & (fft_size - 1)) == 0) fft_size else 1024;
      const actual_n = @min(num_samples, n);

      const allocator = std.heap.c_allocator;

      const re1 = allocator.alloc(f32, n) catch return .{ 0.0, 0.0 };
      defer allocator.free(re1);
      const im1 = allocator.alloc(f32, n) catch return .{ 0.0, 0.0 };
      defer allocator.free(im1);

      const re2 = allocator.alloc(f32, n) catch return .{ 0.0, 0.0 };
      defer allocator.free(re2);
      const im2 = allocator.alloc(f32, n) catch return .{ 0.0, 0.0 };
      defer allocator.free(im2);

      // Load normalized zero-mean I/Q samples with Hann window
      var idx: usize = 0;
      while (idx < n) : (idx += 1) {
          if (idx < actual_n) {
              const hann = 0.5 * (1.0 - std.math.cos(TWO_PI * @as(f32, @floatFromInt(idx)) / @as(f32, @floatFromInt(n))));
              re1[idx] = (@as(f32, @floatFromInt(s1_bytes[idx * 2])) - 127.5) * hann;
              im1[idx] = (@as(f32, @floatFromInt(s1_bytes[idx * 2 + 1])) - 127.5) * hann;

              re2[idx] = (@as(f32, @floatFromInt(s2_bytes[idx * 2])) - 127.5) * hann;
              im2[idx] = (@as(f32, @floatFromInt(s2_bytes[idx * 2 + 1])) - 127.5) * hann;
          } else {
              re1[idx] = 0.0;
              im1[idx] = 0.0;
              re2[idx] = 0.0;
              im2[idx] = 0.0;
          }
      }

      // 1. Compute Forward FFTs
      fft_radix2(re1, im1, n, false);
      fft_radix2(re2, im2, n, false);

      // 2. Cross spectral density with Phase Transform (PHAT whitening):
      // P = X1 * conj(X2) / (|X1 * conj(X2)| + eps)
      const eps: f32 = 1.0e-7;
      idx = 0;
      while (idx < n) : (idx += 1) {
          // X1 * conj(X2):
          // (re1 + j im1) * (re2 - j im2) = (re1 re2 + im1 im2) + j (im1 re2 - re1 im2)
          const re_cross = re1[idx] * re2[idx] + im1[idx] * im2[idx];
          const im_cross = im1[idx] * re2[idx] - re1[idx] * im2[idx];
          const mag = @sqrt(re_cross * re_cross + im_cross * im_cross) + eps;

          re1[idx] = re_cross / mag;
          im1[idx] = im_cross / mag;
      }

      // 3. Compute Inverse FFT to obtain cross-correlation
      fft_radix2(re1, im1, n, true);

      // 4. Find peak lag with circular unwrapping around center lag 0
      // re1[0..n] contains correlation: lags 0..n/2-1 are positive, n/2..n-1 are negative lags
      var max_val: f32 = -1.0;
      var best_idx: usize = 0;

      idx = 0;
      while (idx < n) : (idx += 1) {
          const val = @sqrt(re1[idx] * re1[idx] + im1[idx] * im1[idx]);
          if (val > max_val) {
              max_val = val;
              best_idx = idx;
          }
      }

      // 5. 3-point parabolic interpolation for sub-sample nanosecond resolution
      const prev_idx = (best_idx + n - 1) % n;
      const next_idx = (best_idx + 1) % n;

      const y_prev = @sqrt(re1[prev_idx] * re1[prev_idx] + im1[prev_idx] * im1[prev_idx]);
      const y_peak = max_val;
      const y_next = @sqrt(re1[next_idx] * re1[next_idx] + im1[next_idx] * im1[next_idx]);

      const denom = 2.0 * (y_prev - 2.0 * y_peak + y_next);
      var delta: f32 = 0.0;
      if (@abs(denom) > 1.0e-6) {
          delta = (y_prev - y_next) / denom;
          delta = std.math.clamp(delta, -0.5, 0.5);
      }

      // Map unwrapped lag: if best_idx > n/2, it represents negative lag (best_idx - n)
      const half_n = n / 2;
      var lag_samples: f32 = undefined;
      if (best_idx < half_n) {
          lag_samples = @as(f32, @floatFromInt(best_idx)) + delta;
      } else {
          lag_samples = @as(f32, @floatFromInt(best_idx)) - @as(f32, @floatFromInt(n)) + delta;
      }

      return .{ lag_samples, max_val };
  }

  // Direct time-domain cross-correlation with parabolic interpolation
  // for small slices where FFT is not required
  pub fn time_domain_xcorr(s1: []const f32, s2: []const f32, max_lag: usize) [2]f32 {
      if (s1.len == 0 or s2.len == 0 or max_lag == 0) return .{ 0.0, 0.0 };

      const total_lags = max_lag * 2 + 1;
      const allocator = std.heap.c_allocator;
      const corr = allocator.alloc(f32, total_lags) catch return .{ 0.0, 0.0 };
      defer allocator.free(corr);

      const m = @min(s1.len, s2.len);
      var best_score: f32 = -1.0e9;
      var best_lag_idx: usize = 0;

      var lag_idx: usize = 0;
      while (lag_idx < total_lags) : (lag_idx += 1) {
          const lag = @as(isize, @intCast(lag_idx)) - @as(isize, @intCast(max_lag));
          var sum: f32 = 0.0;
          var count: f32 = 0.0;

          var i: usize = 0;
          while (i < m) : (i += 1) {
              const j_signed = @as(isize, @intCast(i)) + lag;
              if (j_signed >= 0 and j_signed < @as(isize, @intCast(m))) {
                  const j = @as(usize, @intCast(j_signed));
                  sum += s1[i] * s2[j];
                  count += 1.0;
              }
          }

          const score = if (count > 0.0) sum / count else 0.0;
          corr[lag_idx] = score;

          if (score > best_score) {
              best_score = score;
              best_lag_idx = lag_idx;
          }
      }

      // Parabolic refinement
      var delta: f32 = 0.0;
      if (best_lag_idx > 0 and best_lag_idx < total_lags - 1) {
          const y0 = corr[best_lag_idx - 1];
          const y1 = corr[best_lag_idx];
          const y2 = corr[best_lag_idx + 1];
          const denom = 2.0 * (y0 - 2.0 * y1 + y2);
          if (@abs(denom) > 1.0e-6) {
              delta = std.math.clamp((y0 - y2) / denom, -0.5, 0.5);
          }
      }

      const int_lag = @as(f32, @floatFromInt(best_lag_idx)) - @as(f32, @floatFromInt(max_lag));
      return .{ int_lag + delta, best_score };
  }
  """
end
