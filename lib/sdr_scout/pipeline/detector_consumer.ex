defmodule SdrScout.Pipeline.DetectorConsumer do
  @moduledoc """
  GenStage Consumer that feeds incoming raw 64 KB I/Q chunks into the stateful
  Zig SIMD DSP NIF (`SdrScout.Native.Dsp`).
  Forward candidate/verified frames to `SdrScout.Airspace` and tracks telemetry.
  """
  use GenStage
  alias SdrScout.Native.Dsp
  alias SdrScout.Airspace

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    producer = Keyword.fetch!(opts, :producer)
    airspace = Keyword.get(opts, :airspace, Airspace)
    ctx = Dsp.new_context()

    {:consumer, %{ctx: ctx, airspace: airspace},
     subscribe_to: [{producer, max_demand: 4, min_demand: 1}]}
  end

  @impl true
  def handle_events(chunks, _from, state) do
    for chunk <- chunks do
      frames = Dsp.process_chunk(state.ctx, chunk)

      for frame <- frames do
        if state.airspace != nil do
          Airspace.process_frame(frame)
        end
      end
    end

    {:noreply, [], state}
  end
end
