defmodule SdrScout.ModeSTest do
  use ExUnit.Case, async: true
  alias SdrScout.ModeS
  alias SdrScout.TestVectors

  describe "CRC-24 checksum and validation" do
    test "validates known real-world test vectors" do
      assert ModeS.valid?(TestVectors.identification_frame())
      assert ModeS.valid?(TestVectors.airborne_pos_even())
      assert ModeS.valid?(TestVectors.airborne_pos_odd())
      assert ModeS.valid?(TestVectors.airborne_velocity())
    end

    test "detects single bit corruption" do
      <<first::8, rest::binary>> = TestVectors.identification_frame()
      corrupted = <<Bitwise.bxor(first, 1)::8, rest::binary>>
      refute ModeS.valid?(corrupted)
      assert {:error, :crc_checksum_failed} = ModeS.decode(corrupted)
    end

    test "append_crc produces valid 14-byte frame" do
      <<payload::binary-size(11), _parity::binary-size(3)>> = TestVectors.airborne_pos_even()
      frame = ModeS.append_crc(payload)
      assert frame == TestVectors.airborne_pos_even()
      assert ModeS.valid?(frame)
    end
  end

  describe "Unified decode and symmetric encode" do
    test "roundtrip Aircraft Identification" do
      frame = ModeS.encode(:identification, 0x4840D6, "KLM1023")
      assert byte_size(frame) == 14
      assert ModeS.valid?(frame)

      assert {:ok, decoded} = ModeS.decode(frame)
      assert decoded.df == 17
      assert decoded.icao_hex == "4840D6"
      assert decoded.type == :identification
      assert decoded.callsign == "KLM1023"
    end

    test "roundtrip Airborne Position with CPR resolution" do
      lat = 52.3676
      lon = 4.9041
      alt = 32000

      even_frame = ModeS.encode(:airborne_position, 0x4840D6, alt, lat, lon, :even)
      odd_frame = ModeS.encode(:airborne_position, 0x4840D6, alt, lat, lon, :odd)

      assert ModeS.valid?(even_frame)
      assert ModeS.valid?(odd_frame)

      assert {:ok, decoded_even} = ModeS.decode(even_frame)
      assert {:ok, decoded_odd} = ModeS.decode(odd_frame)

      assert decoded_even.altitude == alt
      assert decoded_even.cpr_format == :even
      assert decoded_odd.altitude == alt
      assert decoded_odd.cpr_format == :odd

      even_rep = %{lat_cpr: decoded_even.lat_cpr, lon_cpr: decoded_even.lon_cpr, time: 100}
      odd_rep = %{lat_cpr: decoded_odd.lat_cpr, lon_cpr: decoded_odd.lon_cpr, time: 105}

      assert {:ok, {res_lat, res_lon}} = ModeS.resolve_position(even_rep, odd_rep)
      assert_in_delta res_lat, lat, 0.001
      assert_in_delta res_lon, lon, 0.001
    end

    test "roundtrip Airborne Velocity" do
      speed = 450
      heading = 90.0
      vr = -1200

      frame = ModeS.encode(:airborne_velocity, 0x4840D6, speed, heading, vr)
      assert ModeS.valid?(frame)

      assert {:ok, decoded} = ModeS.decode(frame)
      assert decoded.type == :airborne_velocity
      assert_in_delta decoded.speed, speed, 2
      assert_in_delta decoded.heading, heading, 2.0
      assert decoded.vertical_rate in [-1216, -1200]
    end

    test "encode via map specification" do
      frame = ModeS.encode(%{type: :identification, icao: 0x40621D, callsign: "BAW456"})
      assert ModeS.valid?(frame)
      assert {:ok, decoded} = ModeS.decode(frame)
      assert decoded.callsign == "BAW456"
      assert decoded.icao_hex == "40621D"
    end
  end
end
