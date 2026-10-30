defmodule SdrScout.ModeS.CPR do
  @moduledoc """
  Compact Position Reporting (CPR) decoding and encoding for ADS-B.
  Implements the standard 15-zone latitude/longitude decoding algorithm
  (ICAO Annex 10 / RTCA DO-260B).
  """

  @d_lat_even 360.0 / 60.0
  @d_lat_odd 360.0 / 59.0

  @doc """
  Decodes globally unambiguous latitude and longitude from an Even and Odd CPR report pair.
  `even` and `odd` are maps or tuples containing:
    %{lat_cpr: integer_17_bit, lon_cpr: integer_17_bit, time: timestamp}
  Returns `{:ok, {latitude, longitude}}` or `{:error, reason}`.
  """
  def decode_global(even, odd) do
    # 17-bit CPR coordinates normalized to [0, 1)
    yz_0 = even.lat_cpr / 131_072.0
    yz_1 = odd.lat_cpr / 131_072.0
    xz_0 = even.lon_cpr / 131_072.0
    xz_1 = odd.lon_cpr / 131_072.0

    # 1. Compute latitude index j
    j = floor(59.0 * yz_0 - 60.0 * yz_1 + 0.5)

    r_lat_even = @d_lat_even * (rem_floor(j, 60) + yz_0)
    r_lat_odd = @d_lat_odd * (rem_floor(j, 59) + yz_1)

    r_lat_even = if r_lat_even >= 270.0, do: r_lat_even - 360.0, else: r_lat_even
    r_lat_odd = if r_lat_odd >= 270.0, do: r_lat_odd - 360.0, else: r_lat_odd

    # Check which message is newer
    {lat, nl, is_even_newer} =
      if even.time >= odd.time do
        {r_lat_even, nl(r_lat_even), true}
      else
        {r_lat_odd, nl(r_lat_odd), false}
      end

    if nl(r_lat_even) != nl(r_lat_odd) do
      {:error, :cpr_transition_straddle}
    else
      # 2. Compute longitude
      lon =
        if is_even_newer do
          ni = max(nl, 1)
          d_lon = 360.0 / ni
          m = floor(xz_0 * (nl - 1) - xz_1 * nl + 0.5)
          normalize_lon(d_lon * (rem_floor(m, ni) + xz_0))
        else
          ni = max(nl - 1, 1)
          d_lon = 360.0 / ni
          m = floor(xz_0 * (nl - 1) - xz_1 * nl + 0.5)
          normalize_lon(d_lon * (rem_floor(m, ni) + xz_1))
        end

      {:ok, {Float.round(lat, 5), Float.round(lon, 5)}}
    end
  end

  @doc """
  Encodes a standard latitude and longitude into 17-bit Even and Odd CPR integers.
  Returns `%{even: {lat_cpr, lon_cpr}, odd: {lat_cpr, lon_cpr}}`.
  """
  def encode(lat, lon) do
    # Lat encoding
    lat_even_cpr = round(rem_floor(floor(131_072.0 * (rem_floor(lat, 6.0) / 6.0) + 0.5), 131_072))
    d_lat_odd = 360.0 / 59.0
    lat_odd_cpr = round(rem_floor(floor(131_072.0 * (rem_floor(lat, d_lat_odd) / d_lat_odd) + 0.5), 131_072))

    nl_val = nl(lat)

    # Lon encoding - even
    d_lon_even = if nl_val > 0, do: 360.0 / nl_val, else: 360.0
    lon_even_cpr = round(rem_floor(floor(131_072.0 * (rem_floor(lon, d_lon_even) / d_lon_even) + 0.5), 131_072))

    # Lon encoding - odd
    nl_odd = max(nl_val - 1, 1)
    d_lon_odd = 360.0 / nl_odd
    lon_odd_cpr = round(rem_floor(floor(131_072.0 * (rem_floor(lon, d_lon_odd) / d_lon_odd) + 0.5), 131_072))

    %{
      even: {lat_even_cpr, lon_even_cpr},
      odd: {lat_odd_cpr, lon_odd_cpr}
    }
  end

  # Number of longitude zones NL(lat)
  def nl(lat) when lat in [0.0, 0], do: 59
  def nl(lat) when lat >= 87.0 or lat <= -87.0, do: 1

  def nl(lat) do
    lat_rad = abs(lat) * :math.pi() / 180.0
    numerator = 1.0 - :math.cos(:math.pi() / (2.0 * 15.0))
    denominator = :math.cos(lat_rad) * :math.cos(lat_rad)
    cos_val = 1.0 - numerator / denominator

    if cos_val < -1.0 do
      1
    else
      acos_val = :math.acos(cos_val)
      floor(2.0 * :math.pi() / acos_val)
    end
  end

  defp rem_floor(a, b) do
    a - b * floor(a / b)
  end

  defp normalize_lon(lon) do
    lon = if lon >= 180.0, do: lon - 360.0, else: lon
    if lon < -180.0, do: lon + 360.0, else: lon
  end
end
