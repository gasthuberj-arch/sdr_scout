defmodule SdrScout.Airspace do
  @moduledoc """
  Cluster-ready state tracker for all detected aircraft in airspace.
  Maintains current state per 24-bit ICAO address:
  - Callsign
  - Altitude (ft)
  - Lat / Lon (resolved via CPR odd/even pairing)
  - Speed (knots)
  - Heading (degrees)
  - Vertical rate (ft/min)
  - Messages received count
  - Last updated timestamp

  Publishes state updates via Registry so local (TUI radar) or distributed
  (Phoenix LiveView / multi-node clusters) subscribers can track live movements.
  """
  use GenServer
  alias SdrScout.ModeS.{Decoder, CPR}

  @pubsub_registry SdrScout.Airspace.PubSub

  defstruct [
    :icao,
    :icao_hex,
    :callsign,
    :altitude,
    :latitude,
    :longitude,
    :speed,
    :heading,
    :vertical_rate,
    :cpr_even,
    :cpr_odd,
    :last_seen,
    message_count: 0
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Processes a raw 14-byte Mode-S frame.
  """
  def process_frame(frame) do
    GenServer.cast(__MODULE__, {:process_frame, frame})
  end

  @doc """
  Returns a snapshot map of all currently tracked aircraft.
  """
  def get_airspace do
    GenServer.call(__MODULE__, :get_airspace)
  end

  @doc """
  Subscribes the calling process to real-time airspace updates.
  """
  def subscribe do
    Registry.register(@pubsub_registry, "airspace", [])
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{aircraft: %{}}}
  end

  @impl true
  def handle_call(:get_airspace, _from, state) do
    {:reply, state.aircraft, state}
  end

  @impl true
  def handle_cast({:process_frame, frame}, state) do
    case Decoder.decode(frame) do
      {:ok, decoded} ->
        updated_aircraft = update_aircraft(state.aircraft, decoded)
        {:noreply, %{state | aircraft: updated_aircraft}}

      {:error, _} ->
        {:noreply, state}
    end
  end

  defp update_aircraft(aircraft_map, decoded) do
    icao = decoded.icao
    existing = Map.get(aircraft_map, icao, %__MODULE__{icao: icao, icao_hex: decoded.icao_hex})

    now = System.monotonic_time(:millisecond)

    updated =
      existing
      |> Map.update!(:message_count, &(&1 + 1))
      |> Map.put(:last_seen, now)
      |> apply_message(decoded, now)

    broadcast({:aircraft_updated, updated})
    Map.put(aircraft_map, icao, updated)
  end

  defp apply_message(ac, %{type: :identification, callsign: cs}, _now) do
    %{ac | callsign: cs}
  end

  defp apply_message(
         ac,
         %{type: :airborne_velocity, speed: spd, heading: hdg, vertical_rate: vr},
         _now
       ) do
    %{ac | speed: spd, heading: hdg, vertical_rate: vr}
  end

  defp apply_message(
         ac,
         %{
           type: :airborne_position,
           altitude: alt,
           cpr_format: fmt,
           lat_cpr: lat_cpr,
           lon_cpr: lon_cpr
         },
         now
       ) do
    cpr_report = %{lat_cpr: lat_cpr, lon_cpr: lon_cpr, time: now}

    ac = %{ac | altitude: alt}

    ac =
      case fmt do
        :even -> %{ac | cpr_even: cpr_report}
        :odd -> %{ac | cpr_odd: cpr_report}
      end

    if ac.cpr_even != nil and ac.cpr_odd != nil do
      case CPR.decode_global(ac.cpr_even, ac.cpr_odd) do
        {:ok, {lat, lon}} ->
          %{ac | latitude: lat, longitude: lon}

        {:error, _} ->
          ac
      end
    else
      ac
    end
  end

  defp apply_message(ac, _other, _now), do: ac

  defp broadcast(event) do
    Registry.dispatch(@pubsub_registry, "airspace", fn entries ->
      for {pid, _} <- entries, do: send(pid, event)
    end)
  end
end
