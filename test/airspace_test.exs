defmodule SdrScout.AirspaceTest do
  use ExUnit.Case, async: false
  alias SdrScout.Airspace
  alias SdrScout.TestVectors

  test "updates and evicts aircraft" do
    # Start separate instance with custom name for isolated test
    {:ok, pid} = Airspace.start_link(name: :test_airspace, stale_timeout_ms: 30)

    frame = TestVectors.identification_frame()
    GenServer.cast(pid, {:process_frame, frame})

    Process.sleep(10)
    airspace = GenServer.call(pid, :get_airspace)
    assert map_size(airspace) == 1

    # Wait past stale timeout (30ms) plus eviction tick
    Process.sleep(50)
    send(pid, :evict_stale)

    evicted_airspace = GenServer.call(pid, :get_airspace)
    assert map_size(evicted_airspace) == 0
  end
end
