defmodule SdrScout.TdoaTest do
  use ExUnit.Case, async: true

  alias SdrScout.Native.Tdoa, as: NativeTdoa
  alias SdrScout.Tdoa
  alias SdrScout.Tdoa.Solver
  alias SdrScout.Synth.Tdoa, as: SynthTdoa

  describe "Native GCC-PHAT Delay Estimation" do
    test "estimates zero delay for identical signals" do
      signal =
        for i <- 0..1023, into: <<>> do
          val = round(127.5 + 50.0 * :math.sin(i * 0.1))
          <<val::8, val::8>>
        end

      assert [lag, peak] = NativeTdoa.gcc_phat_delay(signal, signal, 1024)
      assert_in_delta lag, 0.0, 0.1
      assert peak > 0.8
    end

    test "time_domain_xcorr detects discrete lag" do
      s1 = [0.0, 0.0, 1.0, 0.5, 0.0, 0.0, 0.0, 0.0]
      s2 = [0.0, 0.0, 0.0, 0.0, 1.0, 0.5, 0.0, 0.0]
      # s2 is delayed by 2 samples relative to s1

      [lag, score] = NativeTdoa.time_domain_xcorr(s1, s2, 4)
      assert_in_delta lag, 2.0, 0.2
      assert score > 0.0
    end
  end

  describe "Hyperbolic Multilateration Solver" do
    test "solves exact transmitter position from true TDOAs" do
      stations = [
        {0.0, 0.0},
        {10_000.0, 0.0},
        {5_000.0, 10_000.0},
        {12_000.0, 8_000.0}
      ]

      tx_true = {7_500.0, 4_200.0}
      {tx_x, tx_y} = tx_true
      c = Solver.speed_of_light()

      # Compute exact distances and TDOAs
      dists =
        Enum.map(stations, fn {sx, sy} ->
          :math.sqrt(:math.pow(tx_x - sx, 2) + :math.pow(tx_y - sy, 2))
        end)

      [d1 | other_dists] = dists
      tdoas = Enum.map(other_dists, fn d -> (d - d1) / c end)

      assert {:ok, sol} = Solver.solve(stations, tdoas)
      assert_in_delta sol.x, 7_500.0, 0.01
      assert_in_delta sol.y, 4_200.0, 0.01
      assert sol.gdop > 0.0
      assert sol.residual_rms < 1.0e-3
    end

    test "returns error on insufficient stations" do
      assert {:error, :insufficient_stations} = Solver.solve([{0, 0}, {1, 1}], [0.1])
    end

    test "returns error on mismatched TDOA count" do
      assert {:error, :mismatched_tdoa_count} =
               Solver.solve([{0, 0}, {1, 1}, {2, 2}], [0.1, 0.2, 0.3])
    end
  end

  describe "End-to-End TDOA Localization Pipeline" do
    test "localizes synthetic RF burst across 4 synchronized receiver stations" do
      tx_target = {12_000.0, 15_000.0}

      {:ok, sim} =
        SynthTdoa.generate(
          tx_pos: tx_target,
          sample_rate: 2_000_000.0,
          num_samples: 1024
        )

      assert length(sim.recordings) == 4

      # Localize using TDOA
      assert {:ok, result} =
               Tdoa.localize(sim.recordings, sim.stations,
                 sample_rate: 2_000_000.0,
                 fft_size: 1024
               )

      {expected_x, expected_y} = tx_target
      # Should localize emitter position within high accuracy (< 250 meters over a 30 km network)
      assert_in_delta result.x, expected_x, 250.0
      assert_in_delta result.y, expected_y, 250.0
      assert result.gdop > 0.0
    end
  end
end
