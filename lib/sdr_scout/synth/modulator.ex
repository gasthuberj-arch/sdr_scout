defmodule SdrScout.Synth.Modulator do
  @moduledoc """
  Synthesizes raw RTL-SDR compatible 2.0 MSPS complex I/Q baseband signals.
  Input: 14-byte Mode-S frame (112 bits).
  Output: 240 samples (480 bytes) consisting of:
    - 8 µs (16 samples) preamble
    - 112 µs (224 samples) PPM-encoded payload

  Features:
    - Random or specified carrier phase rotation theta
    - Signal amplitude scaling
    - Additive white Gaussian/uniform noise (AWGN)
    - Deliberate bit flip injection for error correction testing
  """
  # 16-sample standard ADS-B preamble: pulses at 0, 2, 7, 9
  @preamble [1, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0]

  @doc """
  Modulates a 14-byte frame into 480 bytes of unsigned 8-bit I/Q pairs.
  Options:
    - `:amplitude` - Signal peak amplitude (default: 100.0, max: 127.0)
    - `:phase` - Carrier phase in radians (default: random)
    - `:snr_noise` - Noise amplitude (default: 10.0)
    - `:flip_bit` - 0-indexed bit to invert in the 112-bit payload (optional)
  """
  def modulate_frame(<<frame::binary-size(14)>>, opts \\ []) do
    amp = Keyword.get(opts, :amplitude, 90.0)
    phase = Keyword.get(opts, :phase, :rand.uniform() * 2.0 * :math.pi())
    noise_amp = Keyword.get(opts, :snr_noise, 8.0)
    flip_bit = Keyword.get(opts, :flip_bit, nil)

    frame_bits = to_bit_list(frame)

    frame_bits =
      if flip_bit != nil and flip_bit in 0..111 do
        List.update_at(frame_bits, flip_bit, fn b -> 1 - b end)
      else
        frame_bits
      end

    # PPM encode bits: 1 -> [1, 0], 0 -> [0, 1]
    ppm_pulses =
      Enum.flat_map(frame_bits, fn
        1 -> [1.0, 0.0]
        0 -> [0.0, 1.0]
      end)

    all_pulses = Enum.map(@preamble, &(&1 * 1.0)) ++ ppm_pulses

    cos_theta = :math.cos(phase)
    sin_theta = :math.sin(phase)

    # Generate I/Q bytes: 127.5 + amp * pulse * cos/sin + noise
    iodata =
      for pulse <- all_pulses do
        noise_i = (:rand.uniform() - 0.5) * 2.0 * noise_amp
        noise_q = (:rand.uniform() - 0.5) * 2.0 * noise_amp

        raw_i = 127.5 + pulse * amp * cos_theta + noise_i
        raw_q = 127.5 + pulse * amp * sin_theta + noise_q

        clamp_u8(raw_i) <> clamp_u8(raw_q)
      end

    IO.iodata_to_binary(iodata)
  end

  @doc """
  Generates a block of pure background noise of `num_samples` (2 * num_samples bytes).
  """
  def generate_noise(num_samples, noise_amp \\ 8.0) do
    iodata =
      for _ <- 1..num_samples do
        noise_i = 127.5 + (:rand.uniform() - 0.5) * 2.0 * noise_amp
        noise_q = 127.5 + (:rand.uniform() - 0.5) * 2.0 * noise_amp
        clamp_u8(noise_i) <> clamp_u8(noise_q)
      end

    IO.iodata_to_binary(iodata)
  end

  defp clamp_u8(val) do
    rounded = round(val)
    clamped = max(0, min(255, rounded))
    <<clamped::8>>
  end

  defp to_bit_list(binary) do
    for <<bit::1 <- binary>>, do: bit
  end
end
