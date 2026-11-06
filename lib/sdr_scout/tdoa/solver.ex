defmodule SdrScout.Tdoa.Solver do
  @moduledoc """
  Hyperbolic Multilateration (MLAT) Solver using non-linear least squares (Gauss-Newton).
  Solves for transmitter 2D position (x, y) from 3 or more GPS-synchronized receiver stations.
  Also calculates Geometric Dilution of Precision (GDOP) and residual RMS error.
  """

  @speed_of_light 299_792_458.0

  @doc """
  Returns the speed of light constant in m/s.
  """
  def speed_of_light, do: @speed_of_light

  @doc """
  Solves for 2D position (x, y) given:
  - `stations`: list of station tuples `[{x1, y1}, {x2, y2}, {x3, y3}, ...]`
  - `tdoa_seconds`: list of TDOA relative to station 1: `[dt21, dt31, ...]`
    (where dt_i1 = t_i - t_1)

  Options:
  - `:initial_guess`: `{x0, y0}` (defaults to centroid of stations)
  - `:max_iters`: maximum Gauss-Newton iterations (default 50)
  - `:tolerance`: convergence step tolerance in meters (default 1.0e-4)

  Returns: `{:ok, %{x: x, y: y, gdop: gdop, iters: iters, residual_rms: rms}}` or `{:error, reason}`
  """
  @spec solve([{number(), number()}], [number()], keyword()) ::
          {:ok, map()} | {:error, atom()}
  def solve(stations, tdoa_seconds, opts \\ [])

  def solve(stations, _tdoa_seconds, _opts) when length(stations) < 3 do
    {:error, :insufficient_stations}
  end

  def solve(stations, tdoa_seconds, _opts) when length(stations) - 1 != length(tdoa_seconds) do
    {:error, :mismatched_tdoa_count}
  end

  def solve(stations, tdoa_seconds, opts) do
    max_iters = Keyword.get(opts, :max_iters, 50)
    tol = Keyword.get(opts, :tolerance, 1.0e-4)

    # Convert TDOA seconds into Range Differences in meters: d_i1 = c * dt_i1
    range_diffs = Enum.map(tdoa_seconds, fn dt -> dt * @speed_of_light end)

    p0 =
      case Keyword.get(opts, :initial_guess) do
        {gx, gy} ->
          {gx * 1.0, gy * 1.0}

        nil ->
          n = length(stations)
          sum_x = Enum.reduce(stations, 0.0, fn {x, _}, acc -> acc + x end)
          sum_y = Enum.reduce(stations, 0.0, fn {_, y}, acc -> acc + y end)
          # Offset centroid slightly to avoid singularity at symmetric station locations
          {sum_x / n + 10.0, sum_y / n + 10.0}
      end

    iterate(stations, range_diffs, p0, 0, max_iters, tol)
  end

  defp iterate(_stations, _d_diffs, {_x, _y}, iter, max_iters, _tol) when iter >= max_iters do
    {:error, :max_iterations_reached}
  end

  defp iterate(stations, d_diffs, {x, y}, iter, max_iters, tol) do
    [{s1_x, s1_y} | other_stations] = stations
    r1 = :math.sqrt(:math.pow(x - s1_x, 2) + :math.pow(y - s1_y, 2))

    if r1 < 1.0e-6 do
      # Nudge position slightly away from receiver 1 to avoid division by zero
      iterate(stations, d_diffs, {x + 0.1, y + 0.1}, iter, max_iters, tol)
    else
      # Build residual vector r and Jacobian J
      {residuals, j_rows} =
        other_stations
        |> Enum.zip(d_diffs)
        |> Enum.reduce({[], []}, fn {{sx, sy}, d_i1}, {r_acc, j_acc} ->
          ri = :math.sqrt(:math.pow(x - sx, 2) + :math.pow(y - sy, 2))
          ri_safe = max(1.0e-6, ri)

          # Residual: (R_i - R_1) - d_i1
          res = ri - r1 - d_i1

          # Jacobian: d(res)/dx, d(res)/dy
          j_x = (x - sx) / ri_safe - (x - s1_x) / r1
          j_y = (y - sy) / ri_safe - (y - s1_y) / r1

          {[res | r_acc], [{j_x, j_y} | j_acc]}
        end)

      r_vec = Enum.reverse(residuals)
      j_mat = Enum.reverse(j_rows)

      # Normal equations: (J^T * J) * delta_p = - J^T * r
      # J is M x 2 matrix
      # J^T * J is 2x2 matrix:
      # [[a, b], [b, c]]
      {a, b, c, g_x, g_y} =
        Enum.zip(j_mat, r_vec)
        |> Enum.reduce({0.0, 0.0, 0.0, 0.0, 0.0}, fn {{jx, jy}, r},
                                                     {acc_a, acc_b, acc_c, acc_gx, acc_gy} ->
          {
            acc_a + jx * jx,
            acc_b + jx * jy,
            acc_c + jy * jy,
            acc_gx + jx * r,
            acc_gy + jy * r
          }
        end)

      # Determinant of 2x2 J^T J
      det = a * c - b * b

      if abs(det) < 1.0e-12 do
        {:error, :singular_geometry}
      else
        # Inverse of J^T J:
        # 1/det * [[c, -b], [-b, a]]
        inv_a = c / det
        inv_b = -b / det
        inv_c = a / det

        # delta_p = - (J^T J)^-1 * (J^T r)
        dx = -(inv_a * g_x + inv_b * g_y)
        dy = -(inv_b * g_x + inv_c * g_y)

        step_norm = :math.sqrt(dx * dx + dy * dy)
        new_x = x + dx
        new_y = y + dy

        if step_norm < tol do
          # Converged!
          # Compute GDOP: sqrt(trace((J^T J)^-1))
          gdop = :math.sqrt(max(0.0, inv_a + inv_c))

          # Residual RMS
          rms = :math.sqrt(Enum.reduce(r_vec, 0.0, fn r, acc -> acc + r * r end) / length(r_vec))

          {:ok,
           %{
             x: new_x,
             y: new_y,
             gdop: gdop,
             iters: iter + 1,
             residual_rms: rms
           }}
        else
          iterate(stations, d_diffs, {new_x, new_y}, iter + 1, max_iters, tol)
        end
      end
    end
  end
end
