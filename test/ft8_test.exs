defmodule SdrScout.Ft8Test do
  use ExUnit.Case, async: true

  alias SdrScout.Ft8
  alias SdrScout.Native.Ft8, as: NativeFt8
  alias SdrScout.Synth.Ft8, as: SynthFt8

  describe "FT8 Protocol & Constants" do
    test "costas_pattern matches WSJT-X FT8 specification" do
      assert Ft8.costas_pattern() == [3, 1, 4, 0, 6, 5, 2]
    end

    test "encode_payload produces 79 symbols with 3 embedded Costas arrays" do
      payload = <<0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x50>>
      tones = Ft8.encode_payload(payload)

      assert length(tones) == 79

      # Costas block 1: symbols 0..6
      assert Enum.slice(tones, 0, 7) == [3, 1, 4, 0, 6, 5, 2]

      # Costas block 2: symbols 36..42
      assert Enum.slice(tones, 36, 7) == [3, 1, 4, 0, 6, 5, 2]

      # Costas block 3: symbols 72..78
      assert Enum.slice(tones, 72, 7) == [3, 1, 4, 0, 6, 5, 2]

      # All symbols must be valid 8-FSK tone indices [0..7]
      assert Enum.all?(tones, fn tone -> tone in 0..7 end)
    end
  end

  describe "CRC-14 & LDPC(174, 91) FEC" do
    test "compute_crc14 generates deterministic 14-bit checksum" do
      payload = <<0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04, 0x05, 0x00>>
      crc = NativeFt8.compute_crc14(payload, 82)
      assert is_integer(crc)
      assert crc >= 0 and crc < 16384
    end

    test "decode_ldpc recovers original payload from pristine LLRs" do
      payload = <<0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0, 0x12, 0x30>>
      tones = Ft8.encode_payload(payload)

      # Construct ideal tone energy matrices for each of the 79 symbols
      symbol_powers =
        Enum.map(tones, fn tone ->
          for t <- 0..7 do
            if t == tone, do: 1.0, else: 0.0
          end
        end)

      llrs = Ft8.symbols_to_llrs(symbol_powers)
      assert length(llrs) == 174

      assert {:ok, decoded_payload, iters} = Ft8.decode_llr(llrs, 25)
      assert iters >= 1
      assert decoded_payload == payload
    end

    test "decode_ldpc corrects channel errors via belief propagation" do
      payload = <<0xCA, 0xFE, 0xBA, 0xBE, 0x11, 0x22, 0x33, 0x44, 0x55, 0x60>>
      tones = Ft8.encode_payload(payload)

      symbol_powers =
        Enum.map(tones, fn tone ->
          for t <- 0..7 do
            if t == tone, do: 1.0, else: 0.05
          end
        end)

      clean_llrs = Ft8.symbols_to_llrs(symbol_powers)

      # Inject 3 bit flips / ambiguous LLRs into the 174 coded bits
      impaired_llrs =
        clean_llrs
        |> List.replace_at(10, -Enum.at(clean_llrs, 10))
        |> List.replace_at(45, -Enum.at(clean_llrs, 45))
        |> List.replace_at(90, 0.0)

      # LDPC belief propagation should correct these errors
      assert {:ok, decoded_payload, _iters} = Ft8.decode_llr(impaired_llrs, 30)
      assert decoded_payload == payload
    end
  end

  describe "End-to-End Modulation & Demodulation Pipeline" do
    test "modulate produces continuous phase samples and matched filter demodulates" do
      payload = <<0x55, 0xAA, 0x55, 0xAA, 0x12, 0x34, 0x56, 0x78, 0x90, 0x00>>

      {:ok, sim} =
        SynthFt8.generate(
          payload: payload,
          sample_rate: 1000.0,
          base_freq: 200.0,
          snr_db: :clean
        )

      assert length(sim.tones) == 79
      assert length(sim.samples) == 79 * round(0.160 * 1000.0)

      # Demodulate tone energies
      demod_energies =
        Ft8.demodulate_symbol_energies(sim.samples,
          sample_rate: 1000.0,
          base_freq: 200.0
        )

      assert length(demod_energies) == 79

      # Verify Costas array synchronization locates start symbol at 0
      assert {:ok, start_idx, score} = Ft8.sync_costas(demod_energies)
      assert start_idx == 0
      assert score > 0.5

      # Decode payload from demodulated energies
      llrs = Ft8.symbols_to_llrs(demod_energies)
      assert {:ok, decoded_payload, _iters} = Ft8.decode_llr(llrs, 25)
      assert decoded_payload == payload
    end

    test "sync_costas rejects streams with insufficient symbols" do
      assert {:error, :not_enough_symbols} = Ft8.sync_costas([])
    end

    test "demodulates and decodes through noisy channel with negative SNR" do
      payload = <<0x46, 0x54, 0x38, 0x20, 0x54, 0x45, 0x53, 0x54, 0x01, 0x20>>

      {:ok, sim} =
        SynthFt8.generate(
          payload: payload,
          sample_rate: 1000.0,
          base_freq: 200.0,
          snr_db: -5.0
        )

      demod_energies =
        Ft8.demodulate_symbol_energies(sim.samples,
          sample_rate: 1000.0,
          base_freq: 200.0
        )

      assert {:ok, 0, _score} = Ft8.sync_costas(demod_energies)

      llrs = Ft8.symbols_to_llrs(demod_energies)
      assert {:ok, decoded_payload, _iters} = Ft8.decode_llr(llrs, 35)
      assert decoded_payload == payload
    end
  end
end
