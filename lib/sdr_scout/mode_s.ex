defmodule SdrScout.ModeS do
  @moduledoc """
  Unified Mode-S Extended Squitter (DF17/DF18) Codec.

  Consolidates:
  - 112-bit frame decoding and field extraction
  - 24-bit CRC polynomial (0x1FFF409) validation and parity generation
  - Compact Position Reporting (CPR) encoding and global surface/airborne decoding
  - Symmetric message encoding for Identification, Airborne Position, and Airborne Velocity
  """
  import Bitwise
  alias SdrScout.ModeS.CPR

  @generator 0x1FFF409
  @ais_charset "#ABCDEFGHIJKLMNOPQRSTUVWXYZ#####_###############0123456789######"

  # ===========================================================================
  # CRC-24 Functions
  # ===========================================================================

  @doc """
  Calculates the 24-bit CRC syndrome / remainder over an arbitrary binary.
  Returns a 24-bit integer.
  """
  def checksum(binary) when is_binary(binary) do
    bits = for <<b::1 <- binary>>, do: b
    do_lfsr(bits, 0)
  end

  defp do_lfsr([], reg), do: band(reg, 0xFFFFFF)

  defp do_lfsr([bit | rest], reg) do
    msb = reg >>> 23 &&& 1
    new_reg = band(reg <<< 1, 0xFFFFFF) ||| bit

    next_reg =
      if msb == 1 do
        bxor(new_reg, @generator)
      else
        new_reg
      end

    do_lfsr(rest, next_reg)
  end

  @doc """
  Verifies that a 112-bit (14-byte) Mode-S frame has a zero CRC remainder.
  """
  def valid?(<<_::binary-size(14)>> = frame) do
    checksum(frame) == 0
  end

  def valid?(_), do: false

  @doc """
  Given an 11-byte (88-bit) message payload, computes the 24-bit parity and
  appends it to produce the complete 14-byte (112-bit) frame.
  """
  def append_crc(<<payload::binary-size(11)>>) do
    parity = checksum(<<payload::binary, 0, 0, 0>>)
    <<payload::binary, parity::24>>
  end

  # ===========================================================================
  # CPR Delegation
  # ===========================================================================

  @doc """
  Encodes a WGS-84 latitude and longitude into CPR even and odd format coordinates.
  """
  defdelegate encode_cpr(lat, lon), to: CPR, as: :encode

  @doc """
  Resolves global latitude and longitude from an even and odd CPR report pair.
  """
  defdelegate resolve_position(even_report, odd_report), to: CPR, as: :decode_global

  # ===========================================================================
  # Frame Decoding
  # ===========================================================================

  @doc """
  Decodes a 14-byte (112-bit) Mode-S Extended Squitter frame (DF17 or DF18).

  Options:
  - `:validate_crc` (boolean, default: `true`): verifies CRC remainder is 0 before parsing.
  """
  def decode(frame, opts \\ [])

  def decode(<<17::5, ca::3, icao::24, me::binary-size(7), pi::24>> = frame, opts) do
    do_decode(17, ca, icao, me, pi, frame, opts)
  end

  def decode(<<18::5, ca::3, icao::24, me::binary-size(7), pi::24>> = frame, opts) do
    do_decode(18, ca, icao, me, pi, frame, opts)
  end

  def decode(_, _opts), do: {:error, :unsupported_format}

  defp do_decode(df, ca, icao, <<tc::5, rest::bitstring>>, pi, raw_frame, opts) do
    validate_crc = Keyword.get(opts, :validate_crc, true)

    if validate_crc and not valid?(raw_frame) do
      {:error, :crc_checksum_failed}
    else
      icao_hex = icao |> Integer.to_string(16) |> String.pad_leading(6, "0")

      base = %{
        df: df,
        ca: ca,
        icao: icao,
        icao_hex: icao_hex,
        type_code: tc,
        pi: pi
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

  # ===========================================================================
  # Frame Encoding
  # ===========================================================================

  @doc """
  Encodes an Aircraft Identification message (TC 1..4) into a 14-byte Mode-S frame.
  """
  def encode_identification(icao, callsign, opts \\ []) do
    ca = Keyword.get(opts, :ca, 5)
    cat = Keyword.get(opts, :category, 1)
    tc = Keyword.get(opts, :tc, 4)

    padded = String.pad_trailing(String.upcase(to_string(callsign)), 8, " ")

    chars =
      for <<char <- padded>> do
        encode_ais_char(char)
      end

    [c1, c2, c3, c4, c5, c6, c7, c8] = chars

    payload =
      <<17::5, ca::3, icao::24, tc::5, cat::3, c1::6, c2::6, c3::6, c4::6, c5::6, c6::6, c7::6,
        c8::6>>

    append_crc(payload)
  end

  @doc """
  Encodes an Airborne Position message (TC 9..18) into a 14-byte Mode-S frame.
  """
  def encode_airborne_position(icao, alt_ft, lat, lon, format, opts \\ []) do
    ca = Keyword.get(opts, :ca, 5)
    tc = Keyword.get(opts, :tc, 11)

    n = round((alt_ft + 1000) / 25)
    alt_raw = (n >>> 4) <<< 5 ||| 1 <<< 4 ||| band(n, 0x0F)

    cpr = CPR.encode(lat, lon)

    {cpr_flag, lat_cpr, lon_cpr} =
      case format do
        :even -> {0, elem(cpr.even, 0), elem(cpr.even, 1)}
        :odd -> {1, elem(cpr.odd, 0), elem(cpr.odd, 1)}
      end

    payload =
      <<17::5, ca::3, icao::24, tc::5, 0::2, 0::1, alt_raw::12, 0::1, cpr_flag::1, lat_cpr::17,
        lon_cpr::17>>

    append_crc(payload)
  end

  @doc """
  Encodes an Airborne Velocity message (TC 19) into a 14-byte Mode-S frame.
  """
  def encode_airborne_velocity(icao, speed_knots, heading_deg, vertical_rate_fpm, opts \\ []) do
    ca = Keyword.get(opts, :ca, 5)
    tc = Keyword.get(opts, :tc, 19)
    subtype = Keyword.get(opts, :subtype, 1)

    rad = heading_deg * :math.pi() / 180.0
    v_ew = speed_knots * :math.sin(rad)
    v_ns = speed_knots * :math.cos(rad)

    s_ew = if v_ew < 0, do: 1, else: 0
    v_ew_raw = round(abs(v_ew)) + 1

    s_ns = if v_ns < 0, do: 1, else: 0
    v_ns_raw = round(abs(v_ns)) + 1

    s_vr = if vertical_rate_fpm < 0, do: 1, else: 0
    vr_raw = if vertical_rate_fpm != 0, do: round(abs(vertical_rate_fpm) / 64) + 1, else: 0

    payload =
      <<17::5, ca::3, icao::24, tc::5, subtype::3, 0::1, 1::1, 1::3, s_ew::1, v_ew_raw::10,
        s_ns::1, v_ns_raw::10, 0::1, s_vr::1, vr_raw::9, 0::10>>

    append_crc(payload)
  end

  @doc """
  Encodes an ADS-B Extended Squitter message via type tag or map.
  """
  def encode(:identification, icao, callsign), do: encode_identification(icao, callsign, [])

  def encode(:identification, icao, callsign, opts),
    do: encode_identification(icao, callsign, opts)

  def encode(:airborne_velocity, icao, speed_knots, heading_deg, vertical_rate_fpm),
    do: encode_airborne_velocity(icao, speed_knots, heading_deg, vertical_rate_fpm, [])

  # encode/6 clauses grouped together
  def encode(:airborne_position, icao, alt_ft, lat, lon, format),
    do: encode_airborne_position(icao, alt_ft, lat, lon, format, [])

  def encode(:airborne_velocity, icao, speed_knots, heading_deg, vertical_rate_fpm, opts),
    do: encode_airborne_velocity(icao, speed_knots, heading_deg, vertical_rate_fpm, opts)

  # encode/7 clause
  def encode(:airborne_position, icao, alt_ft, lat, lon, format, opts),
    do: encode_airborne_position(icao, alt_ft, lat, lon, format, opts)

  def encode(%{type: :identification, icao: icao, callsign: cs} = msg) do
    encode_identification(icao, cs, Map.to_list(msg))
  end

  def encode(
        %{
          type: :airborne_position,
          icao: icao,
          altitude: alt,
          lat: lat,
          lon: lon,
          cpr_format: fmt
        } =
          msg
      ) do
    encode_airborne_position(icao, alt, lat, lon, fmt, Map.to_list(msg))
  end

  def encode(
        %{
          type: :airborne_velocity,
          icao: icao,
          speed: speed,
          heading: heading,
          vertical_rate: vr
        } = msg
      ) do
    encode_airborne_velocity(icao, speed, heading, vr, Map.to_list(msg))
  end

  defp encode_ais_char(char) when char in ?A..?Z, do: char - ?A + 1
  defp encode_ais_char(char) when char in ?0..?9, do: char - ?0 + 48
  defp encode_ais_char(?\s), do: 32
  defp encode_ais_char(_), do: 32
end
