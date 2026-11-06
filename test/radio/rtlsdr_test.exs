defmodule SdrScout.Radio.RtlsdrTest do
  use ExUnit.Case, async: true

  alias SdrScout.Native.Rtlsdr, as: NativeRtlsdr
  alias SdrScout.Radio.Rtlsdr, as: RtlProducer

  describe "Native RTL-SDR Driver Interface" do
    test "opens and closes device context" do
      ctx = NativeRtlsdr.open_device(0)
      assert is_reference(ctx)
      assert :ok = NativeRtlsdr.close_device(ctx)
    end

    test "configures RF center frequency within tuner limits" do
      ctx = NativeRtlsdr.open_device(0)

      # 1090 MHz Mode-S
      assert NativeRtlsdr.set_center_freq(ctx, 1_090_000_000)
      assert NativeRtlsdr.get_center_freq(ctx) == 1_090_000_000

      # 144.390 MHz 2m APRS
      assert NativeRtlsdr.set_center_freq(ctx, 144_390_000)
      assert NativeRtlsdr.get_center_freq(ctx) == 144_390_000

      # Out of bounds: 10 MHz rejected in quadrature mode
      refute NativeRtlsdr.set_center_freq(ctx, 10_000_000)

      # Enable direct sampling: 10 MHz accepted
      assert NativeRtlsdr.set_direct_sampling(ctx, 1)
      assert NativeRtlsdr.set_center_freq(ctx, 10_000_000)
      assert NativeRtlsdr.get_center_freq(ctx) == 10_000_000

      NativeRtlsdr.close_device(ctx)
    end

    test "configures hardware sample rates" do
      ctx = NativeRtlsdr.open_device(0)

      assert NativeRtlsdr.set_sample_rate(ctx, 2_400_000)
      assert NativeRtlsdr.get_sample_rate(ctx) == 2_400_000

      assert NativeRtlsdr.set_sample_rate(ctx, 1_000_000)
      assert NativeRtlsdr.get_sample_rate(ctx) == 1_000_000

      # Reject invalid sample rates
      refute NativeRtlsdr.set_sample_rate(ctx, 100_000)
      refute NativeRtlsdr.set_sample_rate(ctx, 10_000_000)

      NativeRtlsdr.close_device(ctx)
    end

    test "supports 29 R820T2 gain steps and quantizes gain requests" do
      gains = NativeRtlsdr.get_supported_gains()
      assert length(gains) == 29
      assert hd(gains) == 0
      assert List.last(gains) == 496

      ctx = NativeRtlsdr.open_device(0)

      # Set gain 297 (29.7 dB)
      assert NativeRtlsdr.set_tuner_gain(ctx, 297)
      assert NativeRtlsdr.get_tuner_gain(ctx) == 297

      # Requesting 30.0 dB quantizes to 29.7 dB (297)
      assert NativeRtlsdr.set_tuner_gain(ctx, 300)
      assert NativeRtlsdr.get_tuner_gain(ctx) == 297

      NativeRtlsdr.close_device(ctx)
    end

    test "reads 64 KB zero-copy I/Q chunks and updates telemetry" do
      ctx = NativeRtlsdr.open_device(0)

      chunk = NativeRtlsdr.read_samples(ctx, 65_536)
      assert byte_size(chunk) == 65_536

      [freq, rate, bytes, dropped] = NativeRtlsdr.get_telemetry(ctx)
      assert freq == 1_090_000_000
      assert rate == 2_000_000
      assert bytes == 65_536
      assert dropped == 0

      NativeRtlsdr.close_device(ctx)
    end
  end

  describe "GenStage Producer Integration" do
    test "starts producer and emits sample chunks on demand" do
      {:ok, producer} =
        RtlProducer.start_link(
          frequency: 1_090_000_000,
          sample_rate: 2_000_000,
          gain: 29.7,
          chunk_size: 4096
        )

      assert Process.alive?(producer)

      # Change frequency
      assert :ok = RtlProducer.set_frequency(producer, 144_390_000)

      # Check telemetry
      telemetry = RtlProducer.get_telemetry(producer)
      assert telemetry.frequency_hz == 144_390_000
      assert telemetry.sample_rate == 2_000_000
      assert telemetry.tuner_gain_db == 29.7

      # Take 2 chunks via GenStage demand stream
      chunks = GenStage.stream([producer]) |> Enum.take(2)
      assert length(chunks) == 2
      assert Enum.all?(chunks, fn c -> byte_size(c) == 4096 end)

      GenStage.stop(producer)
    end
  end
end
