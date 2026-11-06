defmodule SdrScout.Pipeline.DetectorConsumer do
  @moduledoc """
  GenStage Consumer that feeds incoming raw 64 KB I/Q chunks into the stateful
  Zig SIMD DSP NIF (`SdrScout.Native.Dsp`).
  Forwards verified frames to the configured airspace process and tracks telemetry stats.
  """
  use GenStage
  alias SdrScout.Native.Dsp

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @doc """
  Flushes all in-flight event batches before replying.
  """
  def sync(consumer, timeout \\ 5000) do
    GenStage.call(consumer, :sync, timeout)
  end

  @doc """
  Returns raw DSP telemetry `[samples, preambles, crc_ok, fixed]`.
  """
  def get_telemetry(consumer) do
    GenStage.call(consumer, :get_telemetry)
  end

  @impl true
  def init(opts) do
    producer = Keyword.fetch!(opts, :producer)
    airspace = Keyword.get(opts, :airspace, SdrScout.Airspace)
    collector = Keyword.get(opts, :collector, nil)
    ctx = Dsp.new_context()

    state = %{
      ctx: ctx,
      airspace: airspace,
      collector: collector
    }

    {:consumer, state, subscribe_to: [{producer, max_demand: 4, min_demand: 1}]}
  end

  @impl true
  def handle_call(:get_telemetry, _from, state) do
    telemetry = Dsp.get_telemetry(state.ctx)
    {:reply, telemetry, [], state}
  end

  @impl true
  def handle_call(:sync, _from, state) do
    {:reply, :ok, [], state}
  end

  @impl true
  def handle_events(chunks, _from, state) do
    for chunk <- chunks do
      frames = Dsp.process_chunk(state.ctx, chunk)

      for frame <- frames do
        dispatch_frame(frame, state)
      end
    end

    {:noreply, [], state}
  end

  defp dispatch_frame(frame, state) do
    if is_pid(state.collector) do
      send(state.collector, {:frame, frame})
    end

    cond do
      is_pid(state.airspace) ->
        send(state.airspace, {:"$gen_cast", {:process_frame, frame}})

      is_atom(state.airspace) and state.airspace != nil ->
        GenServer.cast(state.airspace, {:process_frame, frame})

      true ->
        :ok
    end
  end
end
