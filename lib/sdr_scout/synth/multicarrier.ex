defmodule SdrScout.Synth.Multicarrier do
  @moduledoc """
  Synthesizes wideband multi-carrier complex baseband test signals for
  evaluating channelizer isolation, filterbank passband ripple, and adjacent-channel rejection.
  """

  @doc """
  Synthesizes a wideband baseband chunk containing a single complex tone at sub-channel index `target_channel`
  out of `total_channels`.
  """
  def generate_channel_tone(target_channel, total_channels, num_samples, opts \\ []) do
    amplitude = Keyword.get(opts, :amplitude, 90.0)
    noise_amp = Keyword.get(opts, :noise, 0.0)

    # In an M-channel FFT filterbank:
    # Channel k has normalized frequency f_k = k / M (for k in 0..M-1)
    norm_freq = target_channel / total_channels
    d_phase = 2.0 * :math.pi() * norm_freq

    {_phase, iodata} =
      Enum.reduce(0..(num_samples - 1), {0.0, []}, fn _, {phase, acc} ->
        noise_i = if noise_amp > 0, do: (:rand.uniform() - 0.5) * 2.0 * noise_amp, else: 0.0
        noise_q = if noise_amp > 0, do: (:rand.uniform() - 0.5) * 2.0 * noise_amp, else: 0.0

        i_val = 127.5 + amplitude * :math.cos(phase) + noise_i
        q_val = 127.5 + amplitude * :math.sin(phase) + noise_q

        byte_i = min(max(round(i_val), 0), 255)
        byte_q = min(max(round(q_val), 0), 255)

        next_phase = phase + d_phase
        {next_phase, [acc, byte_i, byte_q]}
      end)

    IO.iodata_to_binary(iodata)
  end

  @doc """
  Calculates average RMS energy of an 8-bit unsigned I/Q binary stream.
  """
  def measure_energy(iq_bytes) when is_binary(iq_bytes) do
    num_samples = div(byte_size(iq_bytes), 2)

    if num_samples == 0 do
      0.0
    else
      sum_sq =
        for <<i::8, q::8 <- iq_bytes>>, reduce: 0.0 do
          acc ->
            fi = i - 127.5
            fq = q - 127.5
            acc + (fi * fi + fq * fq)
        end

      :math.sqrt(sum_sq / num_samples)
    end
  end
end
