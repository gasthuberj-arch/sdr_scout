defmodule SdrScout.ModeS.CRCTest do
  use ExUnit.Case, async: true
  alias SdrScout.ModeS.CRC
  alias SdrScout.TestVectors

  test "validates known real-world test vectors" do
    assert CRC.valid?(TestVectors.identification_frame())
    assert CRC.valid?(TestVectors.airborne_pos_even())
    assert CRC.valid?(TestVectors.airborne_pos_odd())
    assert CRC.valid?(TestVectors.airborne_velocity())
  end

  test "detects corrupted frames" do
    <<first::8, rest::binary>> = TestVectors.identification_frame()
    corrupted = <<Bitwise.bxor(first, 1)::8, rest::binary>>
    refute CRC.valid?(corrupted)
  end

  test "encodes 11-byte payload into valid 14-byte frame" do
    <<payload::binary-size(11), _parity::binary-size(3)>> = TestVectors.airborne_pos_even()
    encoded = CRC.encode(payload)
    assert encoded == TestVectors.airborne_pos_even()
    assert CRC.valid?(encoded)
  end
end
