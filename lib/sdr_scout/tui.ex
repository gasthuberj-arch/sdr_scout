defmodule SdrScout.TUI do
  @moduledoc """
  Terminal ANSI radar dashboard with live polar radar scope, aircraft table,
  and DSP telemetry metrics.
  """
  alias SdrScout.Airspace

  @width 60
  @height 20

  @doc """
  Renders a single dashboard frame to string or stdout.
  """
  def render_frame(center_lat \\ 52.0, center_lon \\ 5.0) do
    aircraft_map = Airspace.get_airspace()
    aircraft_list = Map.values(aircraft_map)

    # Build ASCII/Unicode radar grid
    grid =
      for _y <- 0..(@height - 1) do
        for _x <- 0..(@width - 1), do: " "
      end

    # Place center mark (+)
    cx = div(@width, 2)
    cy = div(@height, 2)
    grid = put_cell(grid, cx, cy, "+")

    # Plot aircraft positions
    # Scale: ~2 degrees lat/lon across radar scope
    grid =
      Enum.reduce(aircraft_list, grid, fn ac, acc ->
        if ac.latitude != nil and ac.longitude != nil do
          dx = (ac.longitude - center_lon) * 15.0
          dy = (center_lat - ac.latitude) * 10.0

          x = round(cx + dx)
          y = round(cy + dy)

          if x in 0..(@width - 1) and y in 0..(@height - 1) do
            symbol = if ac.heading, do: heading_arrow(ac.heading), else: "▲"
            put_cell(acc, x, y, symbol)
          else
            acc
          end
        else
          acc
        end
      end)

    # Render border and radar
    radar_str =
      Enum.map_join(grid, "\n", fn row ->
        "│ " <> Enum.join(row) <> " │"
      end)

    header = "┌" <> String.duplicate("─", @width + 2) <> "┐"
    footer = "└" <> String.duplicate("─", @width + 2) <> "┘"

    # Flight table summary
    table =
      if Enum.empty?(aircraft_list) do
        "  (Scanning airspace... waiting for ADS-B squitters)\n"
      else
        header_row = "  ICAO   CALLSIGN  ALT(ft)  SPD(kt)  HDG(°)  LAT, LON\n"

        rows =
          Enum.map_join(aircraft_list, "\n", fn ac ->
            callsign = ac.callsign || "------"
            alt = if ac.altitude, do: "#{ac.altitude}", else: "-----"
            spd = if ac.speed, do: "#{ac.speed}", else: "---"
            hdg = if ac.heading, do: "#{ac.heading}", else: "---"
            pos = if ac.latitude, do: "#{ac.latitude}, #{ac.longitude}", else: "locating..."

            :io_lib.format("  ~6s ~8s ~7s ~8s ~7s  ~s", [
              ac.icao_hex,
              callsign,
              alt,
              spd,
              hdg,
              pos
            ])
            |> IO.iodata_to_binary()
          end)

        header_row <> rows <> "\n"
      end

    """
    #{IO.ANSI.clear()}#{IO.ANSI.home()}
    #{IO.ANSI.cyan()}=== SDR SCOUT: ADS-B 1090 MHz RECEIVER (Zig SIMD + Elixir GenStage) ===#{IO.ANSI.reset()}
    #{header}
    #{radar_str}
    #{footer}
    #{IO.ANSI.yellow()}TRACKED AIRCRAFT (#{length(aircraft_list)} active):#{IO.ANSI.reset()}
    #{table}
    """
  end

  defp put_cell(grid, x, y, char) do
    List.update_at(grid, y, fn row ->
      List.replace_at(row, x, char)
    end)
  end

  defp heading_arrow(hdg) do
    cond do
      hdg >= 337.5 or hdg < 22.5 -> "↑"
      hdg < 67.5 -> "↗"
      hdg < 112.5 -> "→"
      hdg < 157.5 -> "↘"
      hdg < 202.5 -> "↓"
      hdg < 247.5 -> "↙"
      hdg < 292.5 -> "←"
      true -> "↖"
    end
  end
end
