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
    test "decodes standard real-world airborne position test vectors" do
      assert {:ok, even} = ModeS.decode(TestVectors.airborne_pos_even())
      assert {:ok, odd} = ModeS.decode(TestVectors.airborne_pos_odd())

      assert even.icao_hex == "40621D"
      assert even.cpr_format == :even
      assert even.altitude == 38000

      assert odd.icao_hex == "40621D"
      assert odd.cpr_format == :odd
      assert odd.altitude == 38000

      even_report = %{lat_cpr: even.lat_cpr, lon_cpr: even.lon_cpr, time: 100}
      odd_report = %{lat_cpr: odd.lat_cpr, lon_cpr: odd.lon_cpr, time: 105}

      assert {:ok, {lat, lon}} = ModeS.resolve_position(even_report, odd_report)
      assert_in_delta lat, 52.257, 0.05
      assert_in_delta lon, 3.919, 0.05
    end

    test "decodes standard real-world airborne velocity test vector" do
      frame = TestVectors.airborne_velocity()
      assert {:ok, decoded} = ModeS.decode(frame)

      assert decoded.df == 17
      assert decoded.icao_hex == "485020"
      assert decoded.type == :airborne_velocity
      assert decoded.speed > 0
      assert decoded.heading >= 0.0 and decoded.heading <= 360.0
    end

    test "CPR encode and decode roundtrip" do
      test_lat = 52.3676
      test_lon = 4.9041

      cpr = ModeS.encode_cpr(test_lat, test_lon)
      {even_lat_cpr, even_lon_cpr} = cpr.even
      {odd_lat_cpr, odd_lon_cpr} = cpr.odd

      even_rep = %{lat_cpr: even_lat_cpr, lon_cpr: even_lon_cpr, time: 100}
      odd_rep = %{lat_cpr: odd_lat_cpr, lon_cpr: odd_lon_cpr, time: 102}

      assert {:ok, {res_lat, res_lon}} = ModeS.resolve_position(even_rep, odd_rep)
      assert_in_delta res_lat, test_lat, 0.001
      assert_in_delta res_lon, test_lon, 0.001
    end

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
