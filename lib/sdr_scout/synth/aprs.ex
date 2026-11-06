defmodule SdrScout.Synth.APRS do
  @moduledoc """
  Synthesizes raw RTL-SDR compatible complex I/Q baseband signals for Bell 202
  1200-baud AFSK / CPFSK packet radio (AX.25 / APRS).
  Performs HDLC bit stuffing, NRZI encoding, continuous-phase frequency synthesis,
  and baseband I/Q modulation with configurable SNR noise.
  """
  import Bitwise

  @mark_freq 1200.0
  @space_freq 2200.0
  @baud_rate 1200.0

  @doc """
  Synthesizes an AX.25 frame binary into raw 8-bit unsigned I/Q baseband samples.

  Options:
    - `:sample_rate` - Output I/Q sample rate in Hz (default: 48_000, e.g. 40 samples/symbol)
    - `:amplitude` - Signal peak amplitude (default: 90.0, max: 127.0)
    - `:snr_noise` - Noise amplitude (default: 5.0)
    - `:preamble_flags` - Number of 0x7E sync flags before frame (default: 24)
    - `:postamble_flags` - Number of 0x7E trailing flags after frame (default: 4)
  """
  def modulate_ax25(frame_bytes, opts \\ []) when is_binary(frame_bytes) do
    sample_rate = Keyword.get(opts, :sample_rate, 48_000)
    amp = Keyword.get(opts, :amplitude, 90.0)
    noise_amp = Keyword.get(opts, :snr_noise, 5.0)
    preamble_count = Keyword.get(opts, :preamble_flags, 24)
    postamble_count = Keyword.get(opts, :postamble_flags, 4)

    # 1. Generate bit stream with HDLC framing & bit-stuffing
    bits = hdlc_encode(frame_bytes, preamble_count, postamble_count)

    # 2. NRZI encode: 0 toggles tone state, 1 maintains tone state
    # tone state: 1 = Mark (1200 Hz), 0 = Space (2200 Hz)
    tones = nrzi_encode(bits)

    # 3. Continuous-Phase FSK Modulation
    samples_per_symbol = div(sample_rate, round(@baud_rate))
    dt = 1.0 / sample_rate

    # Generate continuous phase I/Q bytes
    {_final_phase, iodata} =
      Enum.reduce(tones, {0.0, []}, fn tone_state, {phase_acc, acc_io} ->
        freq = if tone_state == 1, do: @mark_freq, else: @space_freq
        d_phase = 2.0 * :math.pi() * freq * dt

        {end_phase, symbol_samples} =
          Enum.reduce(1..samples_per_symbol, {phase_acc, []}, fn _, {current_phase, sym_acc} ->
            noise_i = (:rand.uniform() - 0.5) * 2.0 * noise_amp
            noise_q = (:rand.uniform() - 0.5) * 2.0 * noise_amp

            raw_i = 127.5 + amp * :math.cos(current_phase) + noise_i
            raw_q = 127.5 + amp * :math.sin(current_phase) + noise_q

            byte_i = clamp_u8(raw_i)
            byte_q = clamp_u8(raw_q)

            next_phase = current_phase + d_phase
            {next_phase, [sym_acc, byte_i, byte_q]}
          end)

        {end_phase, [acc_io, symbol_samples]}
      end)

    IO.iodata_to_binary(iodata)
  end

  # ===========================================================================
  # HDLC Bit Stuffing & NRZI
  # ===========================================================================

  @doc """
  Encodes raw frame bytes into an HDLC bitstream with pre/postamble flags and bit stuffing.
  """
  def hdlc_encode(frame_bytes, preamble_count, postamble_count) do
    flag_bits = [0, 1, 1, 1, 1, 1, 1, 0]
    preamble = List.duplicate(flag_bits, preamble_count) |> List.flatten()
    postamble = List.duplicate(flag_bits, postamble_count) |> List.flatten()

    # Extract bits LSB first for AX.25
    payload_bits =
      for <<byte <- frame_bytes>> do
        for i <- 0..7, do: byte >>> i &&& 1
      end
      |> List.flatten()

    # Bit stuff: insert 0 after five consecutive 1s
    stuffed_payload = bit_stuff(payload_bits, 0, [])

    preamble ++ stuffed_payload ++ postamble
  end

  defp bit_stuff([], _ones, acc), do: Enum.reverse(acc)

  defp bit_stuff([1 | rest], 4, acc) do
    # Fifth consecutive 1: insert 1, then insert stuffed 0
    bit_stuff(rest, 0, [0, 1 | acc])
  end

  defp bit_stuff([1 | rest], ones, acc) do
    bit_stuff(rest, ones + 1, [1 | acc])
  end

  defp bit_stuff([0 | rest], _ones, acc) do
    bit_stuff(rest, 0, [0 | acc])
  end

  @doc """
  NRZI (Non-Return-to-Zero Inverted) encoding:
  Bit 0 causes transition, bit 1 maintains current state.
  """
  def nrzi_encode(bits) do
    {_final_state, tones} =
      Enum.reduce(bits, {1, []}, fn bit, {current_state, acc} ->
        next_state =
          if bit == 0 do
            1 - current_state
          else
            current_state
          end

        {next_state, [next_state | acc]}
      end)

    Enum.reverse(tones)
  end

  defp clamp_u8(val) do
    rounded = round(val)
    clamped = max(0, min(255, rounded))
    <<clamped::8>>
  end
end
