defmodule SdrScout.ModeS.Decoder do
  @moduledoc """
  Mode-S Extended Squitter (DF17/DF18) Dissector.
  Decodes:
  - Aircraft Identification & Category (TC 1..4)
  - Airborne Position & Barometric Altitude (TC 9..18)
  - Airborne Velocity, Heading, and Vertical Rate (TC 19)
  """
  import Bitwise

  @ais_charset "#ABCDEFGHIJKLMNOPQRSTUVWXYZ#####_###############0123456789######"

  def decode(<<17::5, ca::3, icao::24, me::binary-size(7), pi::24>> = frame) do
    do_decode(17, ca, icao, me, pi, frame)
  end

  def decode(<<18::5, ca::3, icao::24, me::binary-size(7), pi::24>> = frame) do
    do_decode(18, ca, icao, me, pi, frame)
  end

  def decode(_), do: {:error, :unsupported_format}

  defp do_decode(df, ca, icao, <<tc::5, rest::bitstring>>, _pi, _raw) do
    icao_hex = icao |> Integer.to_string(16) |> String.pad_leading(6, "0")

    base = %{
      df: df,
      ca: ca,
      icao: icao,
      icao_hex: icao_hex,
      type_code: tc
    }

    case tc do
      tc when tc in 1..4 ->
        decode_identification(rest, base)

      tc when tc in 9..18 ->
        decode_airborne_position(rest, base)

      19 ->
        decode_airborne_velocity(rest, base)

      _ ->
        {:ok, Map.put(base, :type, :unsupported_tc)}
    end
  end

  # TC 1..4: Aircraft Identification & Category
  defp decode_identification(
         <<cat::3, c1::6, c2::6, c3::6, c4::6, c5::6, c6::6, c7::6, c8::6>>,
         base
       ) do
    chars =
      for c <- [c1, c2, c3, c4, c5, c6, c7, c8], into: "" do
        ch = String.at(@ais_charset, c) || " "
        if ch == "_", do: " ", else: ch
      end

    callsign = String.trim(chars)

    {:ok,
     Map.merge(base, %{
       type: :identification,
       category: cat,
       callsign: callsign
     })}
  end

  defp decode_identification(_, base), do: {:ok, Map.put(base, :type, :identification_invalid)}

  # TC 9..18: Airborne Position
  defp decode_airborne_position(
         <<_ss::2, _saf::1, alt_raw::12, _time::1, cpr_odd::1, lat_cpr::17, lon_cpr::17>>,
         base
       ) do
    altitude = decode_altitude(alt_raw)

    {:ok,
     Map.merge(base, %{
       type: :airborne_position,
       altitude: altitude,
       cpr_format: if(cpr_odd == 1, do: :odd, else: :even),
       lat_cpr: lat_cpr,
       lon_cpr: lon_cpr
     })}
  end

  defp decode_airborne_position(_, base),
    do: {:ok, Map.put(base, :type, :airborne_position_invalid)}

  # 12-bit Barometric altitude decoding
  # Bit 7 (1-based from left, or 0x0010) is Q-bit:
  # Q = 1: 25-ft increments: alt = N * 25 - 1000
  # Q = 0: 100-ft increments (Gillham code)
  defp decode_altitude(raw12) do
    q_bit = band(raw12 >>> 4, 1)

    if q_bit == 1 do
      n = (raw12 >>> 5) <<< 4 ||| band(raw12, 0x000F)
      n * 25 - 1000
    else
      # Fallback for Gillham mode
      nil
    end
  end

  # TC 19: Airborne Velocity
  # Subtypes 1 & 2: Ground speed (Subtype 1: normal, Subtype 2: supersonic)
  # ME layout:
  # TC (5) + Subtype (3) + Intent change (1) + IFR capability (1) + NACv (3) +
  # Direction EW (1) + Velocity EW (10) + Direction NS (1) + Velocity NS (10) +
  # Vert rate source (1) + Vert rate sign (1) + Vert rate (9) + tail (10)
  # Total = 56 bits (7 bytes)
  defp decode_airborne_velocity(
         <<subtype::3, _ic::1, _ifr::1, _nac::3, s_ew::1, v_ew_raw::10, s_ns::1, v_ns_raw::10,
           vr_src::1, s_vr::1, vr_raw::9, _tail::bitstring>>,
         base
       )
       when subtype in [1, 2] do
    v_ew = if s_ew == 1, do: -(v_ew_raw - 1), else: v_ew_raw - 1
    v_ns = if s_ns == 1, do: -(v_ns_raw - 1), else: v_ns_raw - 1

    speed_knots = :math.sqrt(v_ew * v_ew + v_ns * v_ns) |> round()

    heading =
      if speed_knots > 0 do
        rad = :math.atan2(v_ew, v_ns)
        deg = rad * 180.0 / :math.pi()
        deg = if deg < 0, do: deg + 360.0, else: deg
        Float.round(deg, 1)
      else
        0.0
      end

    vertical_rate =
      if vr_raw > 0 do
        val = (vr_raw - 1) * 64
        if s_vr == 1, do: -val, else: val
      else
        0
      end

    {:ok,
     Map.merge(base, %{
       type: :airborne_velocity,
       subtype: subtype,
       speed: speed_knots,
       heading: heading,
       vertical_rate: vertical_rate,
       vertical_rate_src: if(vr_src == 0, do: :baro, else: :geometric)
     })}
  end

  defp decode_airborne_velocity(<<subtype::3, _rest::bitstring>>, base) do
    {:ok, Map.merge(base, %{type: :airborne_velocity, subtype: subtype})}
  end
end
