defmodule SdrScout.TUI.Renderer do
  @moduledoc """
  Pure ANSI terminal rendering engine for the SDR Scout Dashboard.
  Formats spectrum/waterfall graphs, ADS-B airspace radar tables,
  APRS packet feeds, and DSP hardware metrics into double-buffered ANSI frames.
  """

  # ANSI escape codes
  @reset "\e[0m"
  @clear_screen "\e[2J\e[H"
  @hide_cursor "\e[?25l"
  @show_cursor "\e[?25h"
  @alt_screen "\e[?1049h"
  @main_screen "\e[?1049l"

  # Unicode block elements for vertical spectrum bars
  @bars [" ", " ", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

  # ANSI 256 color palette for waterfall & spectrum heatmap
  # Cold Blue -> Cyan -> Green -> Yellow -> Bright Red
  @heat_colors [
    # Deep navy
    "\e[38;5;17m",
    # Navy
    "\e[38;5;18m",
    # Dark Blue
    "\e[38;5;19m",
    # Blue
    "\e[38;5;21m",
    # Azure
    "\e[38;5;27m",
    # Sky Blue
    "\e[38;5;33m",
    # Cyan-Blue
    "\e[38;5;39m",
    # Cyan
    "\e[38;5;45m",
    # Teal
    "\e[38;5;48m",
    # Green
    "\e[38;5;46m",
    # Lime
    "\e[38;5;118m",
    # Yellow-Green
    "\e[38;5;190m",
    # Bright Yellow
    "\e[38;5;226m",
    # Gold
    "\e[38;5;220m",
    # Orange-Yellow
    "\e[38;5;214m",
    # Orange
    "\e[38;5;208m",
    # Red-Orange
    "\e[38;5;202m",
    # Bright Red
    "\e[38;5;196m"
  ]

  @doc """
  Initializes the terminal for TUI mode: switches to alternate screen buffer and hides cursor.
  """
  def init_terminal do
    IO.write([@alt_screen, @hide_cursor, @clear_screen])
  end

  @doc """
  Restores the normal terminal buffer and restores cursor visibility.
  """
  def reset_terminal do
    IO.write([@show_cursor, @main_screen, @reset])
  end

  @doc """
  Renders a full dashboard frame based on state and terminal dimensions.
  """
  def render(state, {cols, _rows}) do
    cols = max(cols, 80)

    header = render_header(state, cols)
    spectrum = render_spectrum(state.spectrum_bins, cols)
    waterfall = render_waterfall(state.waterfall_history, cols, 4)
    airspace = render_airspace(state.aircraft, cols, 7)
    aprs = render_aprs(state.aprs_packets, cols, 5)
    footer = render_footer(cols)

    [
      # Cursor home
      "\e[H",
      header,
      "\n",
      spectrum,
      "\n",
      waterfall,
      "\n",
      airspace,
      "\n",
      aprs,
      "\n",
      footer
    ]
  end

  # ===========================================================================
  # Header & Telemetry Banner
  # ===========================================================================

  defp render_header(state, cols) do
    title = " \e[1;36m⚡ SDR SCOUT\e[0m \e[2mv0.1.0\e[0m \e[90m|\e[0m \e[32mACTIVE\e[0m "

    dsp_msps = state.telemetry[:dsp_msps] || 48.0
    mode_s_count = state.telemetry[:mode_s_count] || 0
    crc_rate = state.telemetry[:crc_rate] || 99.8
    aprs_count = state.telemetry[:aprs_count] || 0
    fixed_bits = state.telemetry[:single_bit_recovered] || 0

    stats =
      "\e[90mMode-S:\e[0m \e[1;37m#{mode_s_count}\e[0m \e[2m(#{crc_rate}% CRC, #{fixed_bits} fixed)\e[0m \e[90m|\e[0m " <>
        "\e[90mAPRS:\e[0m \e[1;33m#{aprs_count} pkts\e[0m \e[90m|\e[0m " <>
        "\e[90mDSP:\e[0m \e[1;35m#{:erlang.float_to_binary(dsp_msps * 1.0, decimals: 1)} MSPS\e[0m "

    border_line = String.duplicate("─", max(cols - 2, 0))

    [
      "\e[1;34m┌",
      border_line,
      "┐\e[0m\n",
      "\e[1;34m│\e[0m",
      title,
      String.duplicate(
        " ",
        max(cols - String.length(strip_ansi(title)) - String.length(strip_ansi(stats)) - 2, 0)
      ),
      stats,
      "\e[1;34m│\e[0m\n",
      "\e[1;34m├",
      border_line,
      "┤\e[0m"
    ]
  end

  # ===========================================================================
  # Live RF Spectrum Visualizer
  # ===========================================================================

  defp render_spectrum(bins, cols) do
    width = cols - 4
    sample_bins = resample_bins(bins, width)

    # Label line
    freq_label =
      " \e[1;37mRF SPECTRUM MONITOR\e[0m \e[90m(1090.0 MHz ADS-B / 144.39 MHz APRS)\e[0m"

    padding = max(cols - String.length(strip_ansi(freq_label)) - 2, 0)

    title_line = [
      "\e[1;34m│\e[0m",
      freq_label,
      String.duplicate(" ", padding),
      "\e[1;34m│\e[0m\n"
    ]

    # Bar graph line
    bars_str =
      Enum.map(sample_bins, fn val ->
        idx = min(round(val * (length(@bars) - 1)), length(@bars) - 1)
        color = pick_heat_color(val)
        [color, Enum.at(@bars, idx), @reset]
      end)

    graph_line = ["\e[1;34m│\e[0m ", bars_str, " \e[1;34m│\e[0m"]

    [title_line, graph_line]
  end

  # ===========================================================================
  # Waterfall Scrolling History
  # ===========================================================================

  defp render_waterfall(history, cols, max_rows) do
    width = cols - 4

    rows =
      history
      |> Enum.take(max_rows)
      |> Enum.map(fn bins ->
        sample_bins = resample_bins(bins, width)

        line =
          Enum.map(sample_bins, fn val ->
            color = pick_heat_color(val)
            # Use half-block or full block for waterfall intensity
            char = if val > 0.1, do: "█", else: " "
            [color, char, @reset]
          end)

        ["\e[1;34m│\e[0m ", line, " \e[1;34m│\e[0m\n"]
      end)

    border_line = String.duplicate("─", max(cols - 2, 0))
    divider = ["\e[1;34m├", border_line, "┤\e[0m\n"]

    [rows, divider]
  end

  # ===========================================================================
  # ADS-B Airspace Contacts Table
  # ===========================================================================

  defp render_airspace(aircraft_map, cols, max_contacts) do
    border_line = String.duplicate("─", max(cols - 2, 0))

    header_cols =
      " \e[1;37mICAO   CALLSIGN  ALTITUDE (FT)  SPEED (KTS)  HEADING  LATITUDE    LONGITUDE    MSGS  AGE\e[0m"

    title_padding = max(cols - String.length(strip_ansi(header_cols)) - 2, 0)

    title_line = [
      "\e[1;34m│\e[0m",
      header_cols,
      String.duplicate(" ", title_padding),
      "\e[1;34m│\e[0m\n"
    ]

    sorted_aircraft =
      aircraft_map
      |> Map.values()
      |> Enum.sort_by(& &1.last_seen, :desc)
      |> Enum.take(max_contacts)

    contact_rows =
      if sorted_aircraft == [] do
        empty_msg = " \e[2;37mScanning 1090 MHz Mode-S baseband for preambles...\e[0m"
        pad = max(cols - String.length(strip_ansi(empty_msg)) - 2, 0)
        [["\e[1;34m│\e[0m", empty_msg, String.duplicate(" ", pad), "\e[1;34m│\e[0m\n"]]
      else
        now = System.monotonic_time(:millisecond)

        Enum.map(sorted_aircraft, fn ac ->
          icao_hex = String.pad_trailing(ac.icao_hex || "UNK", 6)
          callsign = String.pad_trailing(ac.callsign || "-------", 8)
          alt_str = format_alt(ac.altitude)
          spd_str = format_speed(ac.speed)
          hdg_str = format_heading(ac.heading)
          lat_str = format_coord(ac.latitude, 9)
          lon_str = format_coord(ac.longitude, 10)
          msgs_str = String.pad_leading(to_string(ac.message_count || 1), 4)

          age_s = div(max(now - (ac.last_seen || now), 0), 1000)
          age_str = String.pad_leading("#{age_s}s", 4)

          row_str =
            " \e[1;36m#{icao_hex}\e[0m \e[1;37m#{callsign}\e[0m  #{alt_str}     #{spd_str}        #{hdg_str}     #{lat_str}  #{lon_str}   #{msgs_str}  \e[90m#{age_str}\e[0m"

          pad = max(cols - String.length(strip_ansi(row_str)) - 2, 0)
          ["\e[1;34m│\e[0m", row_str, String.duplicate(" ", pad), "\e[1;34m│\e[0m\n"]
        end)
      end

    divider = ["\e[1;34m├", border_line, "┤\e[0m\n"]
    [title_line, contact_rows, divider]
  end

  # ===========================================================================
  # APRS Packet Feed
  # ===========================================================================

  defp render_aprs(packets, cols, max_packets) do
    header = " \e[1;33m📡 APRS PACKET MONITOR\e[0m \e[90m(1200 Baud Bell 202 AFSK)\e[0m"
    pad_h = max(cols - String.length(strip_ansi(header)) - 2, 0)
    title_line = ["\e[1;34m│\e[0m", header, String.duplicate(" ", pad_h), "\e[1;34m│\e[0m\n"]

    rows =
      if packets == [] do
        empty = " \e[2;37mListening for Bell 202 tones on 144.390 MHz...\e[0m"
        pad = max(cols - String.length(strip_ansi(empty)) - 2, 0)
        [["\e[1;34m│\e[0m", empty, String.duplicate(" ", pad), "\e[1;34m│\e[0m\n"]]
      else
        packets
        |> Enum.take(max_packets)
        |> Enum.map(fn pkt ->
          src_badge =
            if pkt.source_ssid > 0 do
              "\e[1;33m#{pkt.source}-#{pkt.source_ssid}\e[0m"
            else
              "\e[1;33m#{pkt.source}\e[0m"
            end

          dest_badge = "\e[90m>\e[0m\e[37m#{pkt.dest}\e[0m"

          digis =
            case pkt.digipeaters do
              [] ->
                ""

              list ->
                "\e[90m via \e[0m" <>
                  Enum.map_join(list, ",", fn {c, s} ->
                    if s > 0, do: "#{c}-#{s}", else: "#{c}"
                  end)
            end

          payload = "\e[32m#{pkt.payload}\e[0m"
          content = " #{src_badge}#{dest_badge}#{digis} : #{payload}"

          pad = max(cols - String.length(strip_ansi(content)) - 2, 0)
          ["\e[1;34m│\e[0m", content, String.duplicate(" ", pad), "\e[1;34m│\e[0m\n"]
        end)
      end

    [title_line, rows]
  end

  # ===========================================================================
  # Footer & Controls
  # ===========================================================================

  defp render_footer(cols) do
    border_line = String.duplicate("─", max(cols - 2, 0))

    controls =
      " \e[2;37m[Q] Quit  [C] Clear Airspace  [R] Reset Stats  [Space] Pause Simulation\e[0m"

    pad = max(cols - String.length(strip_ansi(controls)) - 2, 0)

    [
      "\e[1;34m├",
      border_line,
      "┤\e[0m\n",
      "\e[1;34m│\e[0m",
      controls,
      String.duplicate(" ", pad),
      "\e[1;34m│\e[0m\n",
      "\e[1;34m└",
      border_line,
      "┘\e[0m"
    ]
  end

  # ===========================================================================
  # Formatters & Math Helpers
  # ===========================================================================

  defp format_alt(nil), do: "\e[90m-------\e[0m"
  defp format_alt(alt) when alt >= 30_000, do: "\e[1;35mFL#{div(alt, 100)}\e[0m   "
  defp format_alt(alt) when alt >= 10_000, do: "\e[34m#{String.pad_leading("#{alt}", 5)}\e[0m   "
  defp format_alt(alt), do: "\e[36m#{String.pad_leading("#{alt}", 5)}\e[0m   "

  defp format_speed(nil), do: "\e[90m---\e[0m"
  defp format_speed(spd), do: "\e[37m#{String.pad_leading("#{round(spd)}", 3)}\e[0m"

  defp format_heading(nil), do: "\e[90m---\e[0m"
  defp format_heading(hdg), do: "\e[37m#{String.pad_leading("#{round(hdg)}°", 4)}\e[0m"

  defp format_coord(nil, width), do: String.duplicate(" ", max(width - 3, 0)) <> "\e[90m---\e[0m"

  defp format_coord(val, width) when is_float(val) do
    str = :erlang.float_to_binary(val, decimals: 4)
    String.pad_leading(str, width)
  end

  defp pick_heat_color(val) do
    idx = min(round(val * (length(@heat_colors) - 1)), length(@heat_colors) - 1)
    Enum.at(@heat_colors, idx)
  end

  defp resample_bins([], width), do: List.duplicate(0.0, width)
  defp resample_bins(bins, width) when length(bins) == width, do: bins

  defp resample_bins(bins, width) do
    n_in = length(bins)

    for i <- 0..(width - 1) do
      in_idx = min(div(i * n_in, width), n_in - 1)
      Enum.at(bins, in_idx) || 0.0
    end
  end

  defp strip_ansi(str) do
    Regex.replace(~r/\e\[[0-9;]*[a-zA-Z]/, str, "")
  end
end
