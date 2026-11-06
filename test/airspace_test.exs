defmodule SdrScout.AirspaceTest do
  use ExUnit.Case, async: true
  alias SdrScout.Airspace
  alias SdrScout.TestVectors

  describe "Pure functional transitions" do
    test "ingests identification and airborne position deterministically" do
      airspace = Airspace.new()
      id_frame = TestVectors.identification_frame()

      assert {:ok, ac, airspace} = Airspace.ingest(airspace, id_frame, now: 1_000)
      assert ac.icao_hex == "4840D6"
      assert ac.callsign == "KLM1023"
      assert ac.message_count == 1
      assert ac.last_seen == 1_000

      even_frame = TestVectors.airborne_pos_even()
      assert {:ok, ac_even, airspace} = Airspace.ingest(airspace, even_frame, now: 1_100)
      assert ac_even.altitude == 38000
      assert ac_even.latitude == nil

      odd_frame = TestVectors.airborne_pos_odd()
      assert {:ok, ac_pos, airspace} = Airspace.ingest(airspace, odd_frame, now: 1_200)
      assert ac_pos.latitude != nil
      assert_in_delta ac_pos.latitude, 52.257, 0.05
      assert_in_delta ac_pos.longitude, 3.919, 0.05

      snapshot = Airspace.snapshot(airspace)
      assert map_size(snapshot) == 2
    end

    test "evicts stale tracks using cutoff timestamp" do
      airspace = Airspace.new(stale_timeout_ms: 5_000)
      {:ok, _, airspace} = Airspace.ingest(airspace, TestVectors.identification_frame(), now: 1_000)

      # Before cutoff: track retained
      {evicted_none, airspace} = Airspace.evict_stale(airspace, now: 4_000)
      assert evicted_none == []
      assert map_size(Airspace.snapshot(airspace)) == 1

      # After cutoff: track evicted deterministically
      {evicted, airspace} = Airspace.evict_stale(airspace, now: 7_000)
      assert evicted == [0x4840D6]
      assert map_size(Airspace.snapshot(airspace)) == 0
    end
  end

  describe "Supervised GenServer process lifecycle" do
    test "synchronous ingest/2 and evict_stale/2 without sleeps" do
      {:ok, pid} =
        Airspace.start_link(name: :test_airspace_sync, stale_timeout_ms: 30, schedule_eviction: false)

      frame = TestVectors.identification_frame()
      assert {:ok, ac, snapshot} = Airspace.ingest(pid, frame)
      assert ac.callsign == "KLM1023"
      assert map_size(snapshot) == 1

      # Deterministic eviction without sleep or internal message poking
      future_cutoff = System.monotonic_time(:millisecond) + 1_000
      assert {:ok, [0x4840D6], empty_snapshot} = Airspace.evict_stale(pid, cutoff: future_cutoff)
      assert map_size(empty_snapshot) == 0
      assert Airspace.snapshot(pid) == %{}
    end

    test "asynchronous process_frame/2 cast with instance reference" do
      {:ok, pid} =
        Airspace.start_link(name: :test_airspace_stream, stale_timeout_ms: 50, schedule_eviction: false)

      frame = TestVectors.identification_frame()
      Airspace.process_frame(pid, frame)

      # Snapshot call serializes with the prior cast in mailbox order (deterministic)
      snapshot = Airspace.snapshot(pid)
      assert map_size(snapshot) == 1
      assert Map.has_key?(snapshot, 0x4840D6)
    end
  end
end
