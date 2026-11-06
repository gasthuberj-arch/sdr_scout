defmodule SdrScout.Aircraft do
  @moduledoc """
  Pure domain struct representing an individual tracked aircraft contact.
  """

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

  @doc """
  Constructs a new `Aircraft` struct.
  """
  def new(icao, icao_hex, last_seen \\ nil) do
    %__MODULE__{
      icao: icao,
      icao_hex: icao_hex,
      last_seen: last_seen || System.monotonic_time(:millisecond)
    }
  end
end
