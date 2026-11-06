defmodule SdrScout.Synth.Ft8 do
  @moduledoc """
  Synthetic FT8 Transmission Generator for testing and simulation.
  Supports:
  - Random or deterministic 77-bit test message payloads
  - Multi-tone Continuous-Phase FSK waveform generation
  - Additive White Gaussian Noise (AWGN) injection with precise SNR calibration
  """

  alias SdrScout.Ft8

  @doc """
  Generates a synthetic FT8 packet with optional AWGN channel noise.

  Options:
  - `:payload` - 10-byte binary (default: deterministic test payload)
  - `:sample_rate` - sample rate in Hz (default: 1000.0)
  - `:base_freq` - base carrier frequency in Hz (default: 200.0)
  - `:snr_db` - Signal-to-Noise Ratio in dB (default: :clean, no noise)
  - `:format` - `:complex_f32` (list of `{i, q}`) or `:u8_iq` (raw binary)
  """
  @spec generate(keyword()) :: {:ok, map()}
  def generate(opts \\ []) do
    payload =
      Keyword.get(opts, :payload, <<0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0, 0x12, 0x30>>)

    snr_db = Keyword.get(opts, :snr_db, :clean)
    format = Keyword.get(opts, :format, :complex_f32)
    sample_rate = Keyword.get(opts, :sample_rate, 1000.0)
    base_freq = Keyword.get(opts, :base_freq, 200.0)

    tones = Ft8.encode_payload(payload)

    clean_samples =
      Ft8.modulate(tones,
        sample_rate: sample_rate,
        base_freq: base_freq,
        format: :complex_f32
      )

    noisy_samples =
      case snr_db do
        :clean ->
          clean_samples

        snr when is_number(snr) ->
          # Signal power is 1.0 (unit amplitude complex sinusoid: I^2 + Q^2 = 1.0)
          # SNR_linear = 10^(SNR_db / 10) = P_signal / P_noise = 1.0 / (2 * sigma^2)
          # sigma = sqrt(1.0 / (2 * 10^(snr / 10)))
          noise_sigma = :math.sqrt(1.0 / (2.0 * :math.pow(10.0, snr / 10.0)))

          Enum.map(clean_samples, fn {i, q} ->
            {n_i, n_q} = box_muller(noise_sigma)
            {i + n_i, q + n_q}
          end)
      end

    output_samples =
      case format do
        :complex_f32 ->
          noisy_samples

        :u8_iq ->
          for {i, q} <- noisy_samples, into: <<>> do
            u8_i = round(max(0.0, min(255.0, i * 60.0 + 127.5)))
            u8_q = round(max(0.0, min(255.0, q * 60.0 + 127.5)))
            <<u8_i::8, u8_q::8>>
          end
      end

    {:ok,
     %{
       payload: payload,
       tones: tones,
       num_symbols: length(tones),
       samples: output_samples,
       sample_rate: sample_rate,
       base_freq: base_freq,
       snr_db: snr_db
     }}
  end

  # Standard Box-Muller transform for zero-mean Gaussian random variables
  defp box_muller(sigma) do
    u1 = max(1.0e-12, :rand.uniform())
    u2 = :rand.uniform()
    radius = sigma * :math.sqrt(-2.0 * :math.log(u1))
    theta = 2.0 * :math.pi() * u2
    {radius * :math.cos(theta), radius * :math.sin(theta)}
  end
end
