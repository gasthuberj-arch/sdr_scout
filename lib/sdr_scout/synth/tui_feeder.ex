defmodule SdrScout.Synth.TUIFeeder do
  @moduledoc """
  Generates synthetic flight kinematics, APRS weather and position beacons,
  and dynamic RF spectrum energy for live TUI dashboard demonstrations.
  """
  use GenServer
  alias SdrScout.Airspace
  alias SdrScout.APRS
  alias SdrScout.TUI
  alias SdrScout.TestVectors

  @default_aircraft [
    %{
      icao_hex: "3C4A21",
      callsign: "DLH452",
      alt: 36_000,
      spd: 460.0,
      hdg: 110.0,
      lat: 50.1167,
      lon: 8.6833,
      step: 0.005
    },
    %{
      icao_hex: "4006B2",
      callsign: "BAW117",
      alt: 38_000,
      spd: 485.0,
      hdg: 275.0,
      lat: 51.5074,
      lon: -0.1278,
      step: 0.006
    },
    %{
      icao_hex: "394A50",
      callsign: "AFR834",
      alt: 24_000,
      spd: 390.0,
      hdg: 185.0,
      lat: 48.8566,
      lon: 2.3522,
      step: 0.004
    },
    %{
      icao_hex: "4B1802",
      callsign: "SWR102",
      alt: 11_500,
      spd: 280.0,
      hdg: 65.0,
      lat: 47.4582,
      lon: 8.5555,
      step: 0.003
    },
    %{
      icao_hex: "406B91",
      callsign: "EZY841",
      alt: 5_200,
      spd: 210.0,
      hdg: 340.0,
      lat: 52.3105,
      lon: 4.7683,
      step: 0.002
    }
  ]

  @default_aprs_beacons [
    {"OE1XYZ", 7, "APRS", [{"WIDE1", 1}], "!4812.49N/01622.43E-Vienna APRS Digi & WX"},
    {"KB1GTT", 9, "APRS", [{"WIDE1", 1}, {"WIDE2", 1}],
     "!4221.30N/07103.20W#Mobile SDR Scout Tracker"},
    {"DL1ABC", 1, "APRS", [], "=5230.12N/01323.45E-Berlin VHF Gateway"},
    {"HB9XYZ", 3, "APRS", [{"WIDE2", 2}], "!4722.61N/00832.50E_Zurich Ham Club 144.39MHz"},
    {"ON4KST", 0, "APRS", [], ">50.85N/4.35E Microwave DX Chat Active"}
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def stop do
    if pid = GenServer.whereis(__MODULE__) do
      GenServer.stop(pid)
    end
  end

  # ===========================================================================
  # Callbacks
  # ===========================================================================

  @impl true
  def init(_opts) do
    # Start Airspace server if not started
    unless GenServer.whereis(Airspace) do
      Airspace.start_link()
    end

    schedule_aircraft_tick(250)
    schedule_aprs_tick(1200)
    schedule_spectrum_tick(100)

    state = %{
      aircraft: @default_aircraft,
      aprs_idx: 0,
      mode_s_count: 0,
      dsp_samples: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_info(:aircraft_tick, state) do
    now = System.monotonic_time(:millisecond)

    {updated_aircraft, contacts} =
      Enum.map_reduce(state.aircraft, %{}, fn ac, acc ->
        rad = ac.hdg * :math.pi() / 180.0
        d_lat = :math.cos(rad) * ac.step
        d_lon = :math.sin(rad) * ac.step

        new_lat = ac.lat + d_lat
        new_lon = ac.lon + d_lon

        icao_int = String.to_integer(ac.icao_hex, 16)

        contact = %SdrScout.Aircraft{
          icao: icao_int,
          icao_hex: ac.icao_hex,
          callsign: ac.callsign,
          altitude: ac.alt,
          speed: ac.spd,
          heading: ac.hdg,
          latitude: new_lat,
          longitude: new_lon,
          last_seen: now,
          message_count: state.mode_s_count + 1
        }

        {%{ac | lat: new_lat, lon: new_lon}, Map.put(acc, icao_int, contact)}
      end)

    TUI.update_aircraft(contacts)
    Airspace.process_frame(TestVectors.identification_frame())

    new_mode_s = state.mode_s_count + length(updated_aircraft)

    TUI.update_telemetry(%{
      mode_s_count: new_mode_s,
      dsp_msps: 48.0 + (:rand.uniform() - 0.5) * 1.5
    })

    schedule_aircraft_tick(250)
    {:noreply, %{state | aircraft: updated_aircraft, mode_s_count: new_mode_s}}
  end

  @impl true
  def handle_info(:aprs_tick, state) do
    beacon_count = length(@default_aprs_beacons)
    {call, ssid, dest, digis, payload} = Enum.at(@default_aprs_beacons, state.aprs_idx)

    frame = %APRS{
      source: call,
      source_ssid: ssid,
      dest: dest,
      dest_ssid: 0,
      digipeaters: digis,
      payload: payload
    }

    TUI.push_aprs_packet(frame)

    next_idx = rem(state.aprs_idx + 1, beacon_count)
    schedule_aprs_tick(1500)
    {:noreply, %{state | aprs_idx: next_idx}}
  end

  @impl true
  def handle_info(:spectrum_tick, state) do
    # Generate 64-bin dynamic power spectrum
    # Carrier peak 1 at bin 20 (Mode S pulse energy)
    # Carrier peak 2 at bin 45 (APRS Bell 202 tone shift)
    bins =
      for i <- 0..63 do
        noise = 0.05 + :rand.uniform() * 0.08

        # Mode S Gaussian peak around bin 20
        d1 = abs(i - 20)
        p1 = if d1 < 5, do: 0.85 * :math.exp(-0.25 * d1 * d1), else: 0.0

        # APRS tone peak around bin 45
        d2 = abs(i - 45)
        p2 = if d2 < 4, do: 0.65 * :math.exp(-0.3 * d2 * d2), else: 0.0

        min(noise + p1 + p2, 1.0)
      end

    TUI.update_spectrum(bins)

    schedule_spectrum_tick(100)
    {:noreply, state}
  end

  # ===========================================================================
  # Schedulers
  # ===========================================================================

  defp schedule_aircraft_tick(ms), do: :erlang.send_after(ms, self(), :aircraft_tick)
  defp schedule_aprs_tick(ms), do: :erlang.send_after(ms, self(), :aprs_tick)
  defp schedule_spectrum_tick(ms), do: :erlang.send_after(ms, self(), :spectrum_tick)
end
