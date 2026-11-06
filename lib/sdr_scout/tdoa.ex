defmodule SdrScout.Tdoa do
  @moduledoc """
  Time Difference of Arrival (TDOA) Localization Pipeline.
  Coordinates:
  - GCC-PHAT sub-sample cross-correlation delay estimation via Native Zig NIF
  - Multi-station pairwise TDOA extraction
  - Hyperbolic multilateration emitter position solving
  """

  alias SdrScout.Native.Tdoa, as: NativeTdoa
  alias SdrScout.Tdoa.Solver

  @doc """
  Estimates the time delay between two received I/Q signal chunks using GCC-PHAT.

  Options:
  - `:sample_rate` - sample rate in Hz (default: 2_000_000.0)
  - `:fft_size` - FFT size (default: 1024)

  Returns: `{:ok, %{delay_seconds: tau, delay_samples: lag, peak: peak}}`
  """
  @spec estimate_delay(binary(), binary(), keyword()) :: {:ok, map()}
  def estimate_delay(s1, s2, opts \\ []) when is_binary(s1) and is_binary(s2) do
    sample_rate = Keyword.get(opts, :sample_rate, 2_000_000.0)
    fft_size = Keyword.get(opts, :fft_size, 1024)

    [lag_samples, peak] = NativeTdoa.gcc_phat_delay(s1, s2, fft_size)
    tau_sec = lag_samples / sample_rate

    {:ok,
     %{
       delay_seconds: tau_sec,
       delay_samples: lag_samples,
       peak_correlation: peak
     }}
  end

  @doc """
  Performs complete multi-station TDOA localization.
  Inputs:
  - `recordings`: list of binary sample chunks `[s1, s2, s3, ...]`
  - `stations`: list of station coordinates `[{x1, y1}, {x2, y2}, {x3, y3}, ...]`
  - `opts`: options passed to delay estimator and solver

  Returns: `{:ok, %{x: x, y: y, gdop: gdop, tdoa_seconds: tdoas}}`
  """
  @spec localize([binary()], [{number(), number()}], keyword()) ::
          {:ok, map()} | {:error, atom()}
  def localize(recordings, stations, opts \\ []) do
    if length(recordings) != length(stations) do
      {:error, :mismatched_stations_and_recordings}
    else
      [s1 | other_recordings] = recordings
      sample_rate = Keyword.get(opts, :sample_rate, 2_000_000.0)
      fft_size = Keyword.get(opts, :fft_size, 1024)

      # Measure TDOA dt_i1 for each station i relative to station 1
      tdoa_results =
        Enum.map(other_recordings, fn s_i ->
          # If s_i arrives later than s1, s_i is delayed relative to s1
          # gcc_phat_delay(s_i, s1): lag > 0 means s_i is shifted right
          [lag, _peak] = NativeTdoa.gcc_phat_delay(s_i, s1, fft_size)
          lag / sample_rate
        end)

      case Solver.solve(stations, tdoa_results, opts) do
        {:ok, sol} ->
          {:ok, Map.put(sol, :tdoa_seconds, tdoa_results)}

        error ->
          error
      end
    end
  end
end
