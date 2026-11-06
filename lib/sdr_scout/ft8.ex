defmodule SdrScout.Ft8 do
  @moduledoc """
  FT8 Weak-Signal Protocol Engine & Demodulator.
  Implements:
  - 77-bit message payload pack/unpack
  - Hardware-accurate CRC-14 and LDPC(174, 91) FEC via Native Zig NIF
  - 8-FSK Continuous Phase Frequency Shift Keying (CPFSK) modulation
  - Matched filter tone bank and Costas array synchronization
  """

  alias SdrScout.Native.Ft8, as: NativeFt8

  @costas_pattern [3, 1, 4, 0, 6, 5, 2]
  @tone_spacing 6.25
  @symbol_period 0.160
  @inv_gray_map %{0 => 0, 1 => 1, 3 => 2, 2 => 3, 5 => 4, 6 => 5, 4 => 6, 7 => 7}

  @doc """
  Returns the 7-symbol Costas array synchronization sequence.
  """
  def costas_pattern, do: @costas_pattern

  @doc """
  Encodes a 77-bit binary payload (10 bytes) into 79 8-FSK tone channel symbols.
  """
  @spec encode_payload(binary()) :: [non_neg_integer()]
  def encode_payload(payload) when is_binary(payload) and byte_size(payload) >= 10 do
    payload_10 = binary_part(payload, 0, 10)

    payload_10
    |> NativeFt8.encode_symbols()
    |> :erlang.binary_to_list()
  end

  @doc """
  Decodes 174 Log-Likelihood Ratios into the 77-bit payload.
  Positive LLR indicates bit 0; negative LLR indicates bit 1.
  """
  @spec decode_llr([float()], pos_integer()) ::
          {:ok, binary(), non_neg_integer()} | {:error, atom()}
  def decode_llr(llrs, max_iters \\ 25) when is_list(llrs) do
    NativeFt8.decode_ldpc(llrs, max_iters)
  end

  @doc """
  Converts hard/soft 8-tone channel symbols into bit Log-Likelihood Ratios (LLRs).
  Extracts 58 data symbols (skipping Costas arrays at 0..6, 36..42, 72..78)
  and converts each 8-tone energy vector into 3 bit LLRs.
  """
  @spec symbols_to_llrs([[float()]]) :: [float()]
  def symbols_to_llrs(symbol_powers) when length(symbol_powers) == 79 do
    # Extract only data symbols (29 + 29 = 58 symbols)
    d1 = Enum.slice(symbol_powers, 7, 29)
    d2 = Enum.slice(symbol_powers, 43, 29)
    data_symbols = d1 ++ d2

    Enum.flat_map(data_symbols, fn tone_pwr ->
      tone_energies = if is_list(tone_pwr), do: List.to_tuple(tone_pwr), else: tone_pwr

      # For each bit (MSB to LSB), compute difference between sum of P(bit=0) and P(bit=1)
      for bit_idx <- 0..2 do
        p0 =
          0..7
          |> Enum.filter(fn tone ->
            gray_val = Map.fetch!(@inv_gray_map, tone)
            mask = Bitwise.bsl(1, 2 - bit_idx)
            Bitwise.band(gray_val, mask) == 0
          end)
          |> Enum.map(&elem(tone_energies, &1))
          |> Enum.max()

        p1 =
          0..7
          |> Enum.filter(fn tone ->
            gray_val = Map.fetch!(@inv_gray_map, tone)
            mask = Bitwise.bsl(1, 2 - bit_idx)
            Bitwise.band(gray_val, mask) != 0
          end)
          |> Enum.map(&elem(tone_energies, &1))
          |> Enum.max()

        # LLR: p1 - p0 (positive when bit 1 is more likely, matching LDPC decoder)
        (p1 - p0) * 2.0
      end
    end)
  end

  @doc """
  Modulates 79 8-FSK tone symbols into Continuous-Phase FSK baseband samples.
  Supports `:complex_f32` (list of `{i, q}` floats) or `:u8_iq` (raw interleaved binary).
  """
  @spec modulate([non_neg_integer()] | binary(), keyword()) :: binary() | [{float(), float()}]
  def modulate(tones, opts \\ [])

  def modulate(tones, opts) when is_binary(tones) do
    modulate(:erlang.binary_to_list(tones), opts)
  end

  def modulate(tones, opts) when is_list(tones) and length(tones) == 79 do
    sample_rate = Keyword.get(opts, :sample_rate, 1000.0)
    base_freq = Keyword.get(opts, :base_freq, 200.0)
    format = Keyword.get(opts, :format, :u8_iq)
    samples_per_symbol = round(@symbol_period * sample_rate)

    {samples_rev, _last_phase} =
      Enum.reduce(tones, {[], 0.0}, fn tone, {acc, phase} ->
        freq = base_freq + tone * @tone_spacing
        d_phase = 2.0 * :math.pi() * freq / sample_rate

        {sym_samples, end_phase} =
          Enum.reduce(0..(samples_per_symbol - 1), {[], phase}, fn _, {s_acc, cur_p} ->
            i = :math.cos(cur_p)
            q = :math.sin(cur_p)
            {[{i, q} | s_acc], cur_p + d_phase}
          end)

        {sym_samples ++ acc, end_phase}
      end)

    complex_samples = Enum.reverse(samples_rev)

    case format do
      :complex_f32 ->
        complex_samples

      :u8_iq ->
        for {i, q} <- complex_samples, into: <<>> do
          u8_i = round(max(0.0, min(255.0, i * 120.0 + 127.5)))
          u8_q = round(max(0.0, min(255.0, q * 120.0 + 127.5)))
          <<u8_i::8, u8_q::8>>
        end
    end
  end

  @doc """
  Demodulates 8-FSK tone energies for each symbol block from complex samples.
  """
  @spec demodulate_symbol_energies([{float(), float()}], keyword()) :: [[float()]]
  def demodulate_symbol_energies(samples, opts \\ []) do
    sample_rate = Keyword.get(opts, :sample_rate, 1000.0)
    base_freq = Keyword.get(opts, :base_freq, 200.0)
    samples_per_symbol = round(@symbol_period * sample_rate)
    num_symbols = div(length(samples), samples_per_symbol)

    for s_idx <- 0..(num_symbols - 1) do
      sym_start = s_idx * samples_per_symbol
      sym_samples = Enum.slice(samples, sym_start, samples_per_symbol)

      # 8 tone matched filter power: |sum x[n] e^{-j 2 pi f_k n / fs}|^2
      for tone <- 0..7 do
        f_k = base_freq + tone * @tone_spacing
        w_k = 2.0 * :math.pi() * f_k / sample_rate

        {sum_i, sum_q} =
          sym_samples
          |> Enum.with_index()
          |> Enum.reduce({0.0, 0.0}, fn {{i, q}, n}, {acc_i, acc_q} ->
            angle = w_k * n
            cos_a = :math.cos(angle)
            sin_a = :math.sin(angle)
            # (i + j q) * (cos - j sin) = (i cos + q sin) + j (q cos - i sin)
            {acc_i + (i * cos_a + q * sin_a), acc_q + (q * cos_a - i * sin_a)}
          end)

        (sum_i * sum_i + sum_q * sum_q) / (samples_per_symbol * samples_per_symbol)
      end
    end
  end

  @doc """
  Locates the FT8 frame synchronization using Costas array cross-correlation.
  """
  @spec sync_costas([[float()]]) ::
          {:ok, non_neg_integer(), float()} | {:error, :not_enough_symbols}
  def sync_costas(tone_energies) do
    num_symbols = length(tone_energies)

    if num_symbols < 79 do
      {:error, :not_enough_symbols}
    else
      flat_powers = List.flatten(tone_energies)
      [best_start, score_x100] = NativeFt8.correlate_costas(flat_powers, num_symbols)
      {:ok, best_start, score_x100 / 100.0}
    end
  end
end
