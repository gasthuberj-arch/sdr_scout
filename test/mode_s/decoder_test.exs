defmodule SdrScout.ModeS.DecoderTest do
  use ExUnit.Case, async: true
  alias SdrScout.ModeS.Decoder
  alias SdrScout.ModeS.CPR
  alias SdrScout.TestVectors

  test "decodes Aircraft Identification (TC 4)" do
    frame = TestVectors.identification_frame()
    assert {:ok, decoded} = Decoder.decode(frame)

    assert decoded.df == 17
    assert decoded.icao_hex == "4840D6"
    assert decoded.type == :identification
    assert decoded.callsign == "KLM1023"
  end

  test "decodes Airborne Position and solves CPR lat/lon" do
    assert {:ok, even} = Decoder.decode(TestVectors.airborne_pos_even())
    assert {:ok, odd} = Decoder.decode(TestVectors.airborne_pos_odd())

    assert even.icao_hex == "40621D"
    assert even.cpr_format == :even
    assert even.altitude == 38000

    assert odd.icao_hex == "40621D"
    assert odd.cpr_format == :odd
    assert odd.altitude == 38000

    even_report = %{lat_cpr: even.lat_cpr, lon_cpr: even.lon_cpr, time: 100}
    odd_report = %{lat_cpr: odd.lat_cpr, lon_cpr: odd.lon_cpr, time: 105}

    assert {:ok, {lat, lon}} = CPR.decode_global(even_report, odd_report)
    # Target location in Europe near 52.257, 3.919
    assert_in_delta lat, 52.257, 0.05
    assert_in_delta lon, 3.919, 0.05
  end

  test "decodes Airborne Velocity (TC 19)" do
    frame = TestVectors.airborne_velocity()
    assert {:ok, decoded} = Decoder.decode(frame)

    assert decoded.df == 17
    assert decoded.icao_hex == "485020"
    assert decoded.type == :airborne_velocity
    assert decoded.speed > 0
    assert decoded.heading >= 0.0 and decoded.heading <= 360.0
  end

  test "CPR encode and decode roundtrip" do
    test_lat = 52.3676
    test_lon = 4.9041

    cpr = CPR.encode(test_lat, test_lon)
    {even_lat_cpr, even_lon_cpr} = cpr.even
    {odd_lat_cpr, odd_lon_cpr} = cpr.odd

    even_rep = %{lat_cpr: even_lat_cpr, lon_cpr: even_lon_cpr, time: 100}
    odd_rep = %{lat_cpr: odd_lat_cpr, lon_cpr: odd_lon_cpr, time: 102}

    assert {:ok, {res_lat, res_lon}} = CPR.decode_global(even_rep, odd_rep)
    assert_in_delta res_lat, test_lat, 0.001
    assert_in_delta res_lon, test_lon, 0.001
  end
end
