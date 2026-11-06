defmodule SdrScout.APRS do
  @moduledoc """
  AX.25 Packet Radio and APRS (Automatic Packet Reporting System) protocol codec.
  Encodes and decodes standard 1200 baud Bell 202 VHF APRS frames according to
  the AX.25 2.2 Specification and APRS 1.0.1 Protocol Reference.
  """
  import Bitwise

  @crc16_poly 0x8408

  # ===========================================================================
  # Types & Structs
  # ===========================================================================

  defstruct dest: nil,
            dest_ssid: 0,
            source: nil,
            source_ssid: 0,
            digipeaters: [],
            control: 0x03,
            pid: 0xF0,
            payload: ""

  # ===========================================================================
  # Constructors & Helpers
  # ===========================================================================

  @doc """
  Constructs an APRS uncompressed position report frame (DTI '!').
  Accepts lat and lon in decimal degrees.
  """
  def build_location_report(source, dest, lat, lon, comment, opts \\ []) do
    source_ssid = Keyword.get(opts, :source_ssid, 0)
    dest_ssid = Keyword.get(opts, :dest_ssid, 0)
    digis = Keyword.get(opts, :digipeaters, [])
    sym_table = Keyword.get(opts, :symbol_table, "/")
    sym_code = Keyword.get(opts, :symbol_code, "-")

    pos_str = format_coordinates(lat, lon, sym_table, sym_code)
    payload = "!" <> pos_str <> comment

    %__MODULE__{
      source: source,
      source_ssid: source_ssid,
      dest: dest,
      dest_ssid: dest_ssid,
      digipeaters: digis,
      control: 0x03,
      pid: 0xF0,
      payload: payload
    }
  end

  @doc """
  Formats decimal latitude and longitude into APRS standard DDMM.hhN/DDDMM.hhW format.
  """
  def format_coordinates(lat, lon, sym_table \\ "/", sym_code \\ "-") do
    lat_dir = if lat >= 0, do: "N", else: "S"
    abs_lat = abs(lat)
    lat_deg = trunc(abs_lat)
    lat_min = (abs_lat - lat_deg) * 60.0

    lat_str =
      :io_lib.format("~2..0B~05.2f~s", [lat_deg, lat_min, lat_dir]) |> IO.iodata_to_binary()

    lon_dir = if lon >= 0, do: "E", else: "W"
    abs_lon = abs(lon)
    lon_deg = trunc(abs_lon)
    lon_min = (abs_lon - lon_deg) * 60.0

    lon_str =
      :io_lib.format("~3..0B~05.2f~s", [lon_deg, lon_min, lon_dir]) |> IO.iodata_to_binary()

    lat_str <> sym_table <> lon_str <> sym_code
  end

  # ===========================================================================
  # Encoding API
  # ===========================================================================

  @doc """
  Encodes a callsign string and optional SSID into 7-byte AX.25 address format.
  Callsign characters are left-shifted by 1 bit.
  `last?` sets bit 0 of the SSID byte to 1 if this is the final address in the path.
  """
  def encode_callsign(callsign_str, ssid \\ 0, last? \\ false) do
    # Pad callsign to 6 uppercase characters with spaces
    trimmed = String.upcase(String.trim(callsign_str))
    padded = String.pad_trailing(trimmed, 6, " ") |> binary_part(0, 6)

    # Shift each ASCII character left by 1 bit
    shifted_chars =
      for <<char <- padded>> do
        char <<< 1
      end

    # SSID byte: 0b0110_0000 | (ssid <<< 1) | (if last?, do: 1, else: 0)
    # Bits 5 and 6 are set to 1 in AX.25
    last_bit = if last?, do: 1, else: 0
    ssid_byte = 0x60 ||| (ssid &&& 0x0F) <<< 1 ||| last_bit

    IO.iodata_to_binary(shifted_chars ++ [ssid_byte])
  end

  @doc """
  Encodes an APRS frame struct into a raw un-stuffed AX.25 byte stream (including 16-bit FCS).
  """
  def encode_frame(%__MODULE__{} = frame) do
    dest_bytes = encode_callsign(frame.dest, frame.dest_ssid, false)

    has_digis? = frame.digipeaters != []
    source_bytes = encode_callsign(frame.source, frame.source_ssid, not has_digis?)

    digi_bytes =
      case frame.digipeaters do
        [] ->
          <<>>

        digis ->
          total = length(digis)

          digis
          |> Enum.with_index(1)
          |> Enum.map(fn {{call, ssid}, idx} ->
            encode_callsign(call, ssid, idx == total)
          end)
          |> IO.iodata_to_binary()
      end

    body =
      dest_bytes <>
        source_bytes <>
        digi_bytes <>
        <<frame.control::8, frame.pid::8>> <>
        frame.payload

    fcs = compute_fcs(body)
    fcs_bytes = <<fcs &&& 0xFF::8, fcs >>> 8::8>>

    body <> fcs_bytes
  end

  # ===========================================================================
  # Decoding API
  # ===========================================================================

  @doc """
  Decodes a raw verified AX.25 byte slice (excluding HDLC flags).
  Returns `{:ok, %SdrScout.APRS{}}` or `{:error, reason}`.
  """
  def decode_frame(raw) when byte_size(raw) >= 16 do
    body_len = byte_size(raw) - 2
    <<body::binary-size(^body_len), rx_fcs::little-16>> = raw

    expected_fcs = compute_fcs(body)

    if rx_fcs == expected_fcs do
      parse_body(body)
    else
      {:error, :crc_mismatch}
    end
  end

  def decode_frame(_), do: {:error, :frame_too_short}

  # ===========================================================================
  # CRC-16-CCITT (AX.25 Frame Check Sequence)
  # ===========================================================================

  @doc """
  Computes the 16-bit inverted CRC-16-CCITT checksum for AX.25 packets.
  Uses polynomial 0x8408 (reversed 0x1021) with initial 0xFFFF and final XOR 0xFFFF.
  """
  def compute_fcs(binary) when is_binary(binary) do
    crc =
      for <<byte <- binary>>, reduce: 0xFFFF do
        acc ->
          crc16_byte(byte, acc)
      end

    bxor(crc, 0xFFFF) &&& 0xFFFF
  end

  defp crc16_byte(byte, crc) do
    acc = bxor(crc, byte)

    Enum.reduce(0..7, acc, fn _, c ->
      if (c &&& 0x0001) != 0 do
        bxor(c >>> 1, @crc16_poly)
      else
        c >>> 1
      end
    end)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp parse_body(<<dest_raw::binary-size(7), src_raw::binary-size(7), rest::binary>>) do
    {dest_call, dest_ssid, _} = decode_callsign(dest_raw)
    {src_call, src_ssid, src_last?} = decode_callsign(src_raw)

    {digis, payload_part} =
      if src_last? do
        {[], rest}
      else
        parse_digis(rest, [])
      end

    case payload_part do
      <<control::8, pid::8, payload::binary>> ->
        {:ok,
         %__MODULE__{
           dest: dest_call,
           dest_ssid: dest_ssid,
           source: src_call,
           source_ssid: src_ssid,
           digipeaters: digis,
           control: control,
           pid: pid,
           payload: payload
         }}

      _ ->
        {:error, :malformed_payload}
    end
  end

  defp parse_body(_), do: {:error, :address_too_short}

  defp parse_digis(<<digi_raw::binary-size(7), rest::binary>>, acc) do
    {call, ssid, last?} = decode_callsign(digi_raw)
    new_acc = acc ++ [{call, ssid}]

    if last? do
      {new_acc, rest}
    else
      parse_digis(rest, new_acc)
    end
  end

  defp parse_digis(rest, acc), do: {acc, rest}

  defp decode_callsign(<<c1::8, c2::8, c3::8, c4::8, c5::8, c6::8, ssid_byte::8>>) do
    chars =
      [c1, c2, c3, c4, c5, c6]
      |> Enum.map(&(&1 >>> 1))
      |> List.to_string()
      |> String.trim_trailing()

    ssid = ssid_byte >>> 1 &&& 0x0F
    last? = (ssid_byte &&& 0x01) == 1

    {chars, ssid, last?}
  end
end
