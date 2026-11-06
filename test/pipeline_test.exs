defmodule SdrScout.PipelineTest do
  use ExUnit.Case, async: false
  alias SdrScout.Synth.Scenario
  alias SdrScout.Pipeline
  alias SdrScout.Airspace

  test "synchronous Pipeline.run/2 processes synthetic stream deterministically without sleep" do
    chunks = Scenario.generate_stream(num_chunks: 4)

    assert {:ok, frames, [samples, preambles, crc_ok, _fixed]} =
             Pipeline.run(chunks, airspace: Airspace)

    assert samples >= 4 * 32_768
    assert preambles > 0
    assert crc_ok > 0
    assert length(frames) > 0

    airspace = Airspace.get_airspace()
    assert map_size(airspace) > 0

    aircraft = Map.values(airspace)
    has_callsign = Enum.any?(aircraft, fn a -> a.callsign != nil end)
    assert has_callsign
  end

  test "supervised streaming Pipeline.start_link/1 and drain/1 lifecycle" do
    chunks = Scenario.generate_stream(num_chunks: 2)

    {:ok, pipeline} = Pipeline.start_link(mode: :benchmark, chunks: chunks, airspace: Airspace)
    assert :ok = Pipeline.drain(pipeline)

    telemetry = Pipeline.telemetry(pipeline)
    assert telemetry.samples_processed >= 2 * 32_768
    assert telemetry.preambles_detected > 0

    assert %{producer: p, consumer: c} = Pipeline.get_pids(pipeline)
    assert is_pid(p) and Process.alive?(p)
    assert is_pid(c) and Process.alive?(c)

    Pipeline.stop(pipeline)
    refute Process.alive?(pipeline)
  end
end
