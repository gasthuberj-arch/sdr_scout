defmodule SdrScout.PipelineTest do
  use ExUnit.Case, async: false
  alias SdrScout.Synth.Scenario
  alias SdrScout.Pipeline.{Producer, DetectorConsumer}
  alias SdrScout.Airspace

  test "GenStage pipeline processes synthetic stream through Zig DSP into Airspace" do
    # Generate 4 chunks with multi-aircraft scenario
    chunks = Scenario.generate_stream(num_chunks: 4)

    {:ok, producer} = Producer.start_link(mode: :benchmark, chunks: chunks)
    {:ok, _consumer} = DetectorConsumer.start_link(producer: producer)

    # Allow pipeline to drain demand
    Process.sleep(200)

    airspace = Airspace.get_airspace()
    assert map_size(airspace) > 0

    # Verify at least one tracked aircraft has full telemetry decoded
    aircraft = Map.values(airspace)
    has_callsign = Enum.any?(aircraft, fn a -> a.callsign != nil end)
    assert has_callsign
  end
end
