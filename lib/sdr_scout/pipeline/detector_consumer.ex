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

  @impl true
  def init(opts) do
    producer = Keyword.fetch!(opts, :producer)
    airspace = Keyword.get(opts, :airspace, SdrScout.Airspace)
    ctx = Dsp.new_context()

    {:consumer, %{ctx: ctx, airspace: airspace},
     subscribe_to: [{producer, max_demand: 4, min_demand: 1}]}
  end

  @impl true
  def handle_call(:get_telemetry, _from, state) do
    telemetry = Dsp.get_telemetry(state.ctx)
    {:reply, telemetry, [], state}
  end

  @impl true
  def handle_events(chunks, _from, state) do
    for chunk <- chunks do
      frames = Dsp.process_chunk(state.ctx, chunk)

      for frame <- frames do
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

    {:noreply, [], state}
  end
end
