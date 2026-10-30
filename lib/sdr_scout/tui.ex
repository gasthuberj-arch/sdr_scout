defmodule SdrScout.TUI do
  @moduledoc """
  Terminal ANSI Braille Radar dashboard with polar radar scope,
  tracked aircraft table, and live Zig SIMD DSP telemetry metrics.
  """
  alias SdrScout.Airspace

  # Braille character grid: 2 columns x 4 rows per character
  # Dot map for Unicode 0x2800 offset:
  # dot 1: 0x01 (col 0, row 0)   dot 4: 0x08 (col 1, row 0)
  # dot 2: 0x02 (col 0, row 1)   dot 5: 0x10 (col 1, row 1)
  # dot 3: 0x04 (col 0, row 2)   dot 6: 0x20 (col 1, row 2)
  # dot 7: 0x40 (col 0, row 3)   dot 8: 0x80 (col 1, row 3)
  @char_width 36
  @char_height 18
  @pixel_width @char_width * 2
  @pixel_height @char_height * 4

  @doc """
  Renders a single dashboard frame to string.
  """
  def render_frame(center_lat \\ 52.0, center_lon \\ 5.0, telemetry \\ nil) do
    aircraft_map = Airspace.get_airspace()
    aircraft_list = Map.values(aircraft_map)

    # Pixel bitmap for Braille rendering
    pixels =
      for _y <- 0..(@pixel_height - 1) do
        for _x <- 0..(@pixel_width - 1), do: false
      end

    cx = div(@pixel_width, 2)
    cy = div(@pixel_height, 2)

    # 1. Draw polar range rings (radii: 15, 30, 45 pixels)
    pixels =
      Enum.reduce([12, 24, 34], pixels, fn r, acc ->
        draw_circle(acc, cx, cy, r)
      end)

    # Center crosshair
    pixels = set_pixel(pixels, cx, cy, true)

    # 2. Plot aircraft positions onto pixel canvas
    pixels =
      Enum.reduce(aircraft_list, pixels, fn ac, acc ->
        if ac.latitude != nil and ac.longitude != nil do
          dx = (ac.longitude - center_lon) * 22.0
          dy = (center_lat - ac.latitude) * 14.0

          px = round(cx + dx)
          py = round(cy + dy)

          # Draw 2x2 blip for visibility
          acc
          |> set_pixel(px, py, true)
          |> set_pixel(px + 1, py, true)
          |> set_pixel(px, py + 1, true)
          |> set_pixel(px + 1, py + 1, true)
        else
          acc
        end
      end)

    # 3. Convert pixel canvas to Unicode Braille characters
    braille_rows =
      for cy_idx <- 0..(@char_height - 1) do
        row_str =
          for cx_idx <- 0..(@char_width - 1), into: "" do
            px0 = cx_idx * 2
            py0 = cy_idx * 4

            dot1 = if get_pixel(pixels, px0, py0), do: 0x01, else: 0
            dot2 = if get_pixel(pixels, px0, py0 + 1), do: 0x02, else: 0
            dot3 = if get_pixel(pixels, px0, py0 + 2), do: 0x04, else: 0
            dot7 = if get_pixel(pixels, px0, py0 + 3), do: 0x40, else: 0

            dot4 = if get_pixel(pixels, px0 + 1, py0), do: 0x08, else: 0
            dot5 = if get_pixel(pixels, px0 + 1, py0 + 1), do: 0x10, else: 0
            dot6 = if get_pixel(pixels, px0 + 1, py0 + 2), do: 0x20, else: 0
            dot8 = if get_pixel(pixels, px0 + 1, py0 + 3), do: 0x80, else: 0

            code = 0x2800 + dot1 + dot2 + dot3 + dot4 + dot5 + dot6 + dot7 + dot8
            <<code::utf8>>
          end

        "│ " <> row_str <> " │"
      end

    radar_art = Enum.join(braille_rows, "\n")
    border_w = @char_width + 2
    header_line = "┌" <> String.duplicate("─", border_w) <> "┐"
    footer_line = "└" <> String.duplicate("─", border_w) <> "┘"

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

    # Telemetry bar
    stats_bar =
      case telemetry do
        [samples, preambles, crc_ok, fixed] ->
          "  [DSP STATS] Samples: #{samples} | Preambles: #{preambles} | CRC Valid: #{crc_ok} | 1-Bit Fixed: #{fixed}\n"

        _ ->
          ""
      end

    """
    #{IO.ANSI.clear()}#{IO.ANSI.home()}
    #{IO.ANSI.cyan()}=== SDR SCOUT: ADS-B 1090 MHz RECEIVER (Zig SIMD + Braille Radar Scope) ===#{IO.ANSI.reset()}
    #{header_line}
    #{radar_art}
    #{footer_line}
    #{IO.ANSI.green()}#{stats_bar}#{IO.ANSI.reset()}
    #{IO.ANSI.yellow()}TRACKED AIRCRAFT (#{length(aircraft_list)} active):#{IO.ANSI.reset()}
    #{table}
    """
  end

  defp draw_circle(pixels, cx, cy, radius) do
    # 36 points around ring
    0..35
    |> Enum.reduce(pixels, fn i, acc ->
      theta = i * 2.0 * :math.pi() / 36.0
      x = round(cx + radius * 1.5 * :math.cos(theta))
      y = round(cy + radius * :math.sin(theta))
      set_pixel(acc, x, y, true)
    end)
  end

  defp get_pixel(pixels, x, y) do
    if x in 0..(@pixel_width - 1) and y in 0..(@pixel_height - 1) do
      pixels |> Enum.at(y) |> Enum.at(x)
    else
      false
    end
  end

  defp set_pixel(pixels, x, y, val) do
    if x in 0..(@pixel_width - 1) and y in 0..(@pixel_height - 1) do
      List.update_at(pixels, y, fn row ->
        List.replace_at(row, x, val)
      end)
    else
      pixels
    end
  end
end
