defmodule SdrScout.Native.FskTest do
  use ExUnit.Case, async: true
  alias SdrScout.APRS
  alias SdrScout.Native.Fsk
  alias SdrScout.Synth.APRS, as: SynthAPRS

  setup do
    ctx = Fsk.new_context(48_000.0)
    %{ctx: ctx}
  end

  test "initializes FSK context and returns initial telemetry", %{ctx: ctx} do
    assert is_reference(ctx)
    [samples, packets, crc_errs] = Fsk.get_telemetry(ctx)
    assert samples == 0
    assert packets == 0
    assert crc_errs == 0
  end

  test "demodulates a clean Bell 202 AFSK APRS frame", %{ctx: ctx} do
    frame = %APRS{
      dest: "APRS",
      dest_ssid: 0,
      source: "KB1GTT",
      source_ssid: 9,
      payload: "!4221.30N/07103.20W#Testing SDR Bell 202"
    }

    raw_ax25 = APRS.encode_frame(frame)
    iq = SynthAPRS.modulate_ax25(raw_ax25, sample_rate: 48_000, snr_noise: 0.0)

    decoded = Fsk.process_chunk(ctx, iq)
    assert length(decoded) == 1
    assert hd(decoded) == raw_ax25

    assert {:ok, parsed} = APRS.decode_frame(hd(decoded))
    assert parsed.source == "KB1GTT"
    assert parsed.source_ssid == 9
    assert parsed.payload == frame.payload

    [samples, packets, crc_errs] = Fsk.get_telemetry(ctx)
    assert samples == div(byte_size(iq), 2)
    assert packets == 1
    assert crc_errs == 0
  end

  test "demodulates APRS frame with noise", %{ctx: ctx} do
    frame =
      APRS.build_location_report(
        "HB9XYZ",
        "APRS",
        47.3769,
        8.5417,
        "Zurich Base",
        source_ssid: 3,
        digipeaters: [{"WIDE1", 1}]
      )

    raw_ax25 = APRS.encode_frame(frame)
    iq = SynthAPRS.modulate_ax25(raw_ax25, sample_rate: 48_000, snr_noise: 5.0)

    decoded = Fsk.process_chunk(ctx, iq)
    assert length(decoded) == 1

    assert {:ok, parsed} = APRS.decode_frame(hd(decoded))
    assert parsed.source == "HB9XYZ"
    assert parsed.source_ssid == 3
    assert parsed.digipeaters == [{"WIDE1", 1}]
  end

  test "demodulates multiple successive frames in a single stream", %{ctx: ctx} do
    frame1 = %APRS{
      dest: "APRS",
      source: "W1AW",
      payload: "!4142.80N/07243.20W-ARRL HQ 1"
    }

    frame2 = %APRS{
      dest: "APRS",
      source: "W1AW",
      payload: "!4142.80N/07243.20W-ARRL HQ 2"
    }

    raw1 = APRS.encode_frame(frame1)
    raw2 = APRS.encode_frame(frame2)

    iq1 = SynthAPRS.modulate_ax25(raw1, sample_rate: 48_000, snr_noise: 2.0)
    iq2 = SynthAPRS.modulate_ax25(raw2, sample_rate: 48_000, snr_noise: 2.0)

    stream_iq = iq1 <> iq2
    decoded = Fsk.process_chunk(ctx, stream_iq)

    assert length(decoded) == 2
    assert Enum.at(decoded, 0) == raw1
    assert Enum.at(decoded, 1) == raw2
  end

  test "demodulates across arbitrary chunk boundaries", %{ctx: ctx} do
    frame = %APRS{
      dest: "APRS",
      source: "ON4KST",
      payload: ">Microwave DX chat"
    }

    raw_ax25 = APRS.encode_frame(frame)
    iq = SynthAPRS.modulate_ax25(raw_ax25, sample_rate: 48_000, snr_noise: 3.0)

    # Slice into 1500-byte chunks to force boundaries across symbols & bytes
    chunk_size = 1500

    decoded =
      iq
      |> :erlang.binary_to_list()
      |> Enum.chunk_every(chunk_size)
      |> Enum.flat_map(fn c ->
        Fsk.process_chunk(ctx, :erlang.list_to_binary(c))
      end)

    assert length(decoded) == 1
    assert {:ok, parsed} = APRS.decode_frame(hd(decoded))
    assert parsed.source == "ON4KST"
    assert parsed.payload == ">Microwave DX chat"
  end
end
