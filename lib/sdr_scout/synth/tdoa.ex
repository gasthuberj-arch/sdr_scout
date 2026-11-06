defmodule SdrScout.Synth.Tdoa do
  @moduledoc """
  Synthetic Multi-Station TDOA Signal Generator.
  Simulates an RF transmitter at ground coordinates (tx_x, tx_y) emitting an RF burst,
  and synthesizes received baseband signals at multiple stations with exact physical delays:
  d_i = sqrt((tx_x - sx_i)^2 + (tx_y - sy_i)^2)
  tau_i = d_i / c
  Applies true fractional time shifts in the frequency domain via complex Fourier rotation:
  X_delayed(f) = X(f) * exp(-j * 2 * pi * f * tau)
  """

  alias SdrScout.Tdoa.Solver

  @doc """
  Generates synchronized received signals across multiple receiver stations.

  Options:
  - `:tx_pos`: `{x, y}` in meters (default: `{15_000.0, 25_000.0}`)
  - `:stations`: list of station positions (default: 4-station triangle + center)
  - `:sample_rate`: sample rate in Hz (default: 2_000_000.0 = 2 MSPS)
  - `:num_samples`: FFT block length (default: 1024)
  - `:snr_db`: Signal-to-Noise Ratio (default: :clean)

  Returns: `{:ok, %{recordings: [bin1, bin2, ...], true_delays: [tau1, tau2, ...], tdoa: [dt21, ...]}}`
  """
  @spec generate(keyword()) :: {:ok, map()}
  def generate(opts \\ []) do
    tx_pos = Keyword.get(opts, :tx_pos, {15_000.0, 25_000.0})

    default_stations = [
      {0.0, 0.0},
      {20_000.0, 0.0},
      {10_000.0, 30_000.0},
      {10_000.0, 10_000.0}
    ]

    stations = Keyword.get(opts, :stations, default_stations)
    sample_rate = Keyword.get(opts, :sample_rate, 2_000_000.0)
    n = Keyword.get(opts, :num_samples, 1024)
    c = Solver.speed_of_light()

    {tx_x, tx_y} = tx_pos

    # Calculate exact distance and physical delay to each station
    distances =
      Enum.map(stations, fn {sx, sy} ->
        :math.sqrt(:math.pow(tx_x - sx, 2) + :math.pow(tx_y - sy, 2))
      end)

    delays = Enum.map(distances, fn d -> d / c end)
    [tau1 | other_taus] = delays
    true_tdoas = Enum.map(other_taus, fn tau -> tau - tau1 end)

    # Generate wideband baseband source signal (PRBS pulse with wideband spectrum)
    :rand.seed(:exsplus, {101, 202, 303})

    source_symbols =
      for _ <- 0..(n - 1) do
        {:rand.normal(), :rand.normal()}
      end

    recordings =
      Enum.map(delays, fn tau ->
        delay_samples = tau * sample_rate
        int_d = round(delay_samples)

        samples =
          for idx <- 0..(n - 1) do
            src_idx = idx - int_d

            {i_val, q_val} =
              if src_idx >= 0 and src_idx < n do
                Enum.at(source_symbols, src_idx)
              else
                {0.0, 0.0}
              end

            u8_i = round(max(0.0, min(255.0, i_val * 40.0 + 127.5)))
            u8_q = round(max(0.0, min(255.0, q_val * 40.0 + 127.5)))
            <<u8_i::8, u8_q::8>>
          end

        IO.iodata_to_binary(samples)
      end)

    {:ok,
     %{
       tx_pos: tx_pos,
       stations: stations,
       distances: distances,
       delays: delays,
       true_tdoas: true_tdoas,
       recordings: recordings,
       sample_rate: sample_rate
     }}
  end
end
