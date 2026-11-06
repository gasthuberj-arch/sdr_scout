defmodule SdrScout.Radio.Rtlsdr do
  @moduledoc """
  GenStage Producer for native RTL-SDR hardware streaming.
  Ingests raw 64 KB refc binary chunks from the Zig RTL2832U driver and streams
  them downstream with backpressure to SDR processing pipelines.
  """
  use GenStage

  alias SdrScout.Native.Rtlsdr, as: NativeRtlsdr

  @default_chunk_size 65_536

  # Client API

  @doc """
  Starts the RTL-SDR GenStage Producer process.

  Options:
  - `:device_index` - USB device index (default: 0)
  - `:frequency` - center frequency in Hz (default: 1_090_000_000 = 1090 MHz)
  - `:sample_rate` - sample rate in Hz (default: 2_000_000 = 2 MSPS)
  - `:gain` - tuner gain in dB (float, e.g. 29.7, or :auto for AGC)
  - `:chunk_size` - bytes per buffer chunk (default: 65536 = 64 KB)
  - `:direct_sampling` - 0=off, 1=I, 2=Q for HF reception (default: 0)
  """
  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts)
  end

  @doc """
  Re-tunes the hardware center frequency in Hz.
  """
  def set_frequency(producer, freq_hz) when is_integer(freq_hz) do
    GenStage.call(producer, {:set_frequency, freq_hz})
  end

  @doc """
  Sets the hardware tuner gain.
  """
  def set_gain(producer, gain_db) when is_number(gain_db) or gain_db == :auto do
    GenStage.call(producer, {:set_gain, gain_db})
  end

  @doc """
  Retrieves device streaming telemetry and hardware metrics.
  """
  def get_telemetry(producer) do
    GenStage.call(producer, :get_telemetry)
  end

  # GenStage Callbacks

  @impl true
  def init(opts) do
    device_index = Keyword.get(opts, :device_index, 0)
    freq_hz = Keyword.get(opts, :frequency, 1_090_000_000)
    sample_rate = Keyword.get(opts, :sample_rate, 2_000_000)
    gain = Keyword.get(opts, :gain, 29.7)
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    direct_sampling = Keyword.get(opts, :direct_sampling, 0)

    ctx = NativeRtlsdr.open_device(device_index)

    if direct_sampling > 0 do
      NativeRtlsdr.set_direct_sampling(ctx, direct_sampling)
    end

    NativeRtlsdr.set_sample_rate(ctx, sample_rate)
    NativeRtlsdr.set_center_freq(ctx, freq_hz)

    case gain do
      :auto ->
        NativeRtlsdr.set_agc_mode(ctx, true)

      val when is_number(val) ->
        NativeRtlsdr.set_agc_mode(ctx, false)
        NativeRtlsdr.set_tuner_gain(ctx, round(val * 10.0))
    end

    state = %{
      ctx: ctx,
      chunk_size: chunk_size,
      device_index: device_index,
      demand: 0
    }

    {:producer, state}
  end

  @impl true
  def handle_demand(demand, state) when demand > 0 do
    chunks =
      for _ <- 1..demand do
        NativeRtlsdr.read_samples(state.ctx, state.chunk_size)
      end

    {:noreply, chunks, state}
  end

  @impl true
  def handle_call({:set_frequency, freq_hz}, _from, state) do
    ok = NativeRtlsdr.set_center_freq(state.ctx, freq_hz)
    {:reply, if(ok, do: :ok, else: {:error, :out_of_range}), [], state}
  end

  @impl true
  def handle_call({:set_gain, :auto}, _from, state) do
    NativeRtlsdr.set_agc_mode(state.ctx, true)
    {:reply, :ok, [], state}
  end

  @impl true
  def handle_call({:set_gain, gain_db}, _from, state) do
    NativeRtlsdr.set_agc_mode(state.ctx, false)
    ok = NativeRtlsdr.set_tuner_gain(state.ctx, round(gain_db * 10.0))
    {:reply, if(ok, do: :ok, else: {:error, :invalid_gain}), [], state}
  end

  @impl true
  def handle_call(:get_telemetry, _from, state) do
    [freq, rate, bytes, dropped] = NativeRtlsdr.get_telemetry(state.ctx)

    telemetry = %{
      frequency_hz: freq,
      sample_rate: rate,
      bytes_streamed: bytes,
      dropped_samples: dropped,
      tuner_gain_db: NativeRtlsdr.get_tuner_gain(state.ctx) / 10.0
    }

    {:reply, telemetry, [], state}
  end

  @impl true
  def terminate(_reason, state) do
    if Map.has_key?(state, :ctx) do
      NativeRtlsdr.close_device(state.ctx)
    end

    :ok
  end
end
