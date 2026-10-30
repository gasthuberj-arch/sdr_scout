defmodule SdrScout.Native.DspTest do
  use ExUnit.Case, async: true
  alias SdrScout.Native.Dsp
  alias SdrScout.Synth.Modulator
  alias SdrScout.TestVectors

  test "detects clean frame and updates telemetry" do
    ctx = Dsp.new_context()
    assert is_reference(ctx)

    frame = TestVectors.identification_frame()
    iq = Modulator.modulate_frame(frame, snr_noise: 2.0)
    chunk = Modulator.generate_noise(500, 2.0) <> iq <> Modulator.generate_noise(500, 2.0)

    detected = Dsp.process_chunk(ctx, chunk)
    assert detected == [frame]

    [samples, preambles, crc_ok, single_bit_fixed] = Dsp.get_telemetry(ctx)
    assert samples == 1240
    assert preambles == 1
    assert crc_ok == 1
    assert single_bit_fixed == 0
  end

  test "corrects single bit flip via 1-bit syndrome recovery" do
    ctx = Dsp.new_context()
    frame = TestVectors.airborne_pos_even()

    # Invert bit 35 in payload
    corrupted_iq = Modulator.modulate_frame(frame, flip_bit: 35, snr_noise: 2.0)

    chunk =
      Modulator.generate_noise(500, 2.0) <> corrupted_iq <> Modulator.generate_noise(500, 2.0)

    detected = Dsp.process_chunk(ctx, chunk)
    assert detected == [frame]

    [_samples, preambles, crc_ok, single_bit_fixed] = Dsp.get_telemetry(ctx)
    assert preambles == 1
    assert crc_ok == 0
    assert single_bit_fixed == 1
  end

  test "recovers frames straddling chunk boundaries using overlap buffer" do
    ctx = Dsp.new_context()
    frame = TestVectors.airborne_pos_odd()

    iq = Modulator.modulate_frame(frame, snr_noise: 2.0)
    <<head_100::binary-size(100), tail_380::binary-size(380)>> = iq

    chunk1 = Modulator.generate_noise(500, 2.0) <> head_100
    chunk2 = tail_380 <> Modulator.generate_noise(500, 2.0)

    assert Dsp.process_chunk(ctx, chunk1) == []
    assert Dsp.process_chunk(ctx, chunk2) == [frame]
  end
end
