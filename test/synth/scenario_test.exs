defmodule SdrScout.Synth.ScenarioTest do
  use ExUnit.Case, async: true
  alias SdrScout.Synth.Scenario
  alias SdrScout.ModeS.{CRC, Decoder}

  test "generates valid scenario frames" do
    id_frame = Scenario.make_identification_frame(0x4840D6, "KLM1023")
    assert CRC.valid?(id_frame)
    assert {:ok, %{type: :identification, callsign: "KLM1023"}} = Decoder.decode(id_frame)

    pos_even = Scenario.make_airborne_pos_frame(0x4840D6, 32000, 52.3676, 4.9041, :even)
    assert CRC.valid?(pos_even)
    assert {:ok, %{type: :airborne_position, altitude: 32000, cpr_format: :even}} = Decoder.decode(pos_even)

    pos_odd = Scenario.make_airborne_pos_frame(0x4840D6, 32000, 52.3676, 4.9041, :odd)
    assert CRC.valid?(pos_odd)
    assert {:ok, %{type: :airborne_position, altitude: 32000, cpr_format: :odd}} = Decoder.decode(pos_odd)

    vel_frame = Scenario.make_airborne_velocity_frame(0x4840D6, 450, 90.0, -1200)
    assert CRC.valid?(vel_frame)
    assert {:ok, decoded_vel} = Decoder.decode(vel_frame)
    assert decoded_vel.type == :airborne_velocity
    assert_in_delta decoded_vel.speed, 450, 2
    assert_in_delta decoded_vel.heading, 90.0, 2.0
    assert decoded_vel.vertical_rate == -1216 or decoded_vel.vertical_rate == -1200
  end

  test "generates multi-chunk stream of 64 KB blocks" do
    chunks = Scenario.generate_stream(num_chunks: 3)
    assert length(chunks) == 3
    for chunk <- chunks do
      assert byte_size(chunk) == 65_536
    end
  end
end
