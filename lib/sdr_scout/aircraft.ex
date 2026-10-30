defmodule SdrScout.Aircraft do
  @moduledoc """
  Domain model for an individual tracked aircraft.
  Handles kinematic state and message updates.
  """
  alias SdrScout.ModeS.CPR

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

  def new(icao, icao_hex) do
    %__MODULE__{
      icao: icao,
      icao_hex: icao_hex,
      last_seen: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Applies a decoded ADS-B message payload to the aircraft record.
  """
  def apply_message(%__MODULE__{} = ac, decoded, timestamp) do
    ac
    |> Map.update!(:message_count, &(&1 + 1))
    |> Map.put(:last_seen, timestamp)
    |> do_apply(decoded, timestamp)
  end

  defp do_apply(ac, %{type: :identification, callsign: cs}, _time) do
    %{ac | callsign: cs}
  end

  defp do_apply(
         ac,
         %{type: :airborne_velocity, speed: spd, heading: hdg, vertical_rate: vr},
         _time
       ) do
    %{ac | speed: spd, heading: hdg, vertical_rate: vr}
  end

  defp do_apply(
         ac,
         %{
           type: :airborne_position,
           altitude: alt,
           cpr_format: fmt,
           lat_cpr: lat_cpr,
           lon_cpr: lon_cpr
         },
         time
       ) do
    cpr_report = %{lat_cpr: lat_cpr, lon_cpr: lon_cpr, time: time}
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

  defp do_apply(ac, _other, _time), do: ac
end
