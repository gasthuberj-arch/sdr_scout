defmodule SdrScout.TUITest do
  use ExUnit.Case, async: false
  alias SdrScout.TUI
  alias SdrScout.TUI.Renderer
  alias SdrScout.Aircraft
  alias SdrScout.APRS

  describe "Renderer" do
    test "renders empty dashboard without crashing" do
      state = %{
        aircraft: %{},
        aprs_packets: [],
        spectrum_bins: List.duplicate(0.1, 64),
        waterfall_history: [List.duplicate(0.1, 64)],
        telemetry: %{
          dsp_msps: 48.0,
          mode_s_count: 0,
          crc_rate: 100.0,
          aprs_count: 0,
          single_bit_recovered: 0
        }
      }

      output = IO.iodata_to_binary(Renderer.render(state, {100, 30}))
      assert output =~ "SDR SCOUT"
      assert output =~ "RF SPECTRUM MONITOR"
      assert output =~ "APRS PACKET MONITOR"
      assert output =~ "Scanning 1090 MHz Mode-S"
    end

    test "renders active aircraft contacts in radar table" do
      ac = %Aircraft{
        icao: 0x3C4A21,
        icao_hex: "3C4A21",
        callsign: "DLH452",
        altitude: 35_000,
        speed: 450.0,
        heading: 95.0,
        latitude: 50.1234,
        longitude: 8.5678,
        message_count: 42,
        last_seen: System.monotonic_time(:millisecond)
      }

      state = %{
        aircraft: %{0x3C4A21 => ac},
        aprs_packets: [],
        spectrum_bins: List.duplicate(0.2, 64),
        waterfall_history: [],
        telemetry: %{dsp_msps: 48.0, mode_s_count: 42}
      }

      output = IO.iodata_to_binary(Renderer.render(state, {110, 30}))
      assert output =~ "3C4A21"
      assert output =~ "DLH452"
      assert output =~ "FL350"
      assert output =~ "450"
      assert output =~ "95°"
      assert output =~ "50.1234"
      assert output =~ "8.5678"
    end

    test "renders APRS packets with badges and digipeaters" do
      pkt = %APRS{
        source: "OE1XYZ",
        source_ssid: 7,
        dest: "APRS",
        digipeaters: [{"WIDE1", 1}],
        payload: "!4812.49N/01622.43E-Vienna Ham Station"
      }

      state = %{
        aircraft: %{},
        aprs_packets: [pkt],
        spectrum_bins: List.duplicate(0.05, 64),
        waterfall_history: [],
        telemetry: %{aprs_count: 1}
      }

      output = IO.iodata_to_binary(Renderer.render(state, {100, 30}))
      assert output =~ "OE1XYZ-7"
      assert output =~ "APRS"
      assert output =~ "WIDE1-1"
      assert output =~ "Vienna Ham Station"
    end
  end

  describe "TUI Process" do
    test "starts and handles telemetry and packet updates" do
      {:ok, pid} = TUI.start_link(interactive?: false, refresh_interval_ms: 50)
      assert Process.alive?(pid)

      TUI.update_spectrum(List.duplicate(0.75, 64))

      pkt = %APRS{
        source: "KB1GTT",
        dest: "APRS",
        payload: ">Test Beacon"
      }

      TUI.push_aprs_packet(pkt)
      TUI.update_telemetry(%{dsp_msps: 52.4, mode_s_count: 100})

      paused? = TUI.toggle_pause()
      assert paused? == true

      TUI.stop()
      refute Process.alive?(pid)
    end
  end
end
