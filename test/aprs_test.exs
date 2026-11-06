defmodule SdrScout.APRSTest do
  use ExUnit.Case, async: true
  import Bitwise
  alias SdrScout.APRS

  describe "callsign encoding & decoding" do
    test "encodes standard callsign with no SSID and not last" do
      encoded = APRS.encode_callsign("W3ADO", 0, false)
      assert byte_size(encoded) == 7
      # Callsign shifted left by 1, SSID has 0x60
      assert encoded == <<?W <<< 1, ?3 <<< 1, ?A <<< 1, ?D <<< 1, ?O <<< 1, ?\s <<< 1, 0x60>>
    end

    test "encodes callsign with SSID and last bit set" do
      encoded = APRS.encode_callsign("N0CALL", 9, true)
      assert byte_size(encoded) == 7
      # 0x60 | (9 <<< 1) | 1 = 0x60 | 18 | 1 = 96 + 18 + 1 = 115 (0x73)
      assert encoded == <<?N <<< 1, ?0 <<< 1, ?C <<< 1, ?A <<< 1, ?L <<< 1, ?L <<< 1, 0x73>>
    end
  end

  describe "FCS checksum" do
    test "matches expected CCITT CRC-16" do
      test_data = "Hello World AX.25 FCS Test"
      fcs = APRS.compute_fcs(test_data)
      assert is_integer(fcs)
      assert fcs == 0x36E1
    end
  end

  describe "frame encode & decode roundtrip" do
    test "encodes and decodes direct unproto frame" do
      frame = %APRS{
        dest: "APRS",
        dest_ssid: 0,
        source: "DL1ABC",
        source_ssid: 7,
        payload: "!5230.12N/01323.45E-SDR Scout Station"
      }

      raw = APRS.encode_frame(frame)
      assert byte_size(raw) >= 16

      assert {:ok, decoded} = APRS.decode_frame(raw)
      assert decoded.dest == "APRS"
      assert decoded.dest_ssid == 0
      assert decoded.source == "DL1ABC"
      assert decoded.source_ssid == 7
      assert decoded.digipeaters == []
      assert decoded.payload == "!5230.12N/01323.45E-SDR Scout Station"
    end

    test "encodes and decodes frame with digipeater path" do
      frame = %APRS{
        dest: "APRS",
        dest_ssid: 0,
        source: "G4KLX",
        source_ssid: 1,
        digipeaters: [{"WIDE1", 1}, {"WIDE2", 2}],
        payload: ">Testing APRS digipeater path"
      }

      raw = APRS.encode_frame(frame)
      assert {:ok, decoded} = APRS.decode_frame(raw)
      assert decoded.source == "G4KLX"
      assert decoded.source_ssid == 1
      assert decoded.digipeaters == [{"WIDE1", 1}, {"WIDE2", 2}]
      assert decoded.payload == ">Testing APRS digipeater path"
    end

    test "build_location_report helper formats coordinates and payload correctly" do
      frame =
        APRS.build_location_report(
          "OE1XYZ",
          "APRS",
          48.2082,
          16.3738,
          "Vienna Scout",
          source_ssid: 5,
          digipeaters: [{"WIDE1", 1}]
        )

      assert frame.source == "OE1XYZ"
      assert frame.source_ssid == 5
      assert frame.digipeaters == [{"WIDE1", 1}]
      assert frame.payload =~ "!4812.49N/01622.43E-Vienna Scout"

      raw = APRS.encode_frame(frame)
      assert {:ok, decoded} = APRS.decode_frame(raw)
      assert decoded.source == "OE1XYZ"
      assert decoded.payload == frame.payload
    end

    test "rejects corrupted frame" do
      frame = %APRS{
        dest: "APRS",
        source: "N0CALL",
        payload: "!5000.00N/01000.00E#Test"
      }

      raw = APRS.encode_frame(frame)
      <<head::binary-size(10), corrupted_byte::8, rest::binary>> = raw
      bad_raw = <<head::binary, bxor(corrupted_byte, 0xFF)::8, rest::binary>>

      assert {:error, :crc_mismatch} = APRS.decode_frame(bad_raw)
    end
  end
end
