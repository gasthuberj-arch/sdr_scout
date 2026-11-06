defmodule SdrScout.Native.PfbTest do
  use ExUnit.Case, async: true
  alias SdrScout.PFB
  alias SdrScout.Synth.Multicarrier

  test "initializes 16-channel PFB context with Blackman-Harris window" do
    pfb = PFB.new(16, taps_per_branch: 8, window: :blackman_harris)
    assert pfb.num_channels == 16
    assert pfb.taps_per_branch == 8
    assert length(pfb.prototype_taps) == 16 * 8

    # DC sum of taps should be normalized to ~1.0
    assert_in_delta Enum.sum(pfb.prototype_taps), 1.0, 0.001

    [samples, blocks] = PFB.get_telemetry(pfb)
    assert samples == 0
    assert blocks == 0
  end

  test "channelizes tone at Channel 0 with high adjacent channel isolation" do
    num_channels = 8
    taps_per_branch = 8
    pfb = PFB.new(num_channels, taps_per_branch: taps_per_branch, window: :blackman_harris)

    # Generate 512 samples with tone at channel 0
    iq = Multicarrier.generate_channel_tone(0, num_channels, 512, amplitude: 90.0)

    channels = PFB.channelize(pfb, iq)
    assert length(channels) == num_channels

    # Each channel should produce 512 / 8 = 64 complex samples (128 bytes)
    assert byte_size(hd(channels)) == 128

    energies = Enum.map(channels, &Multicarrier.measure_energy/1)
    ch0_energy = Enum.at(energies, 0)
    ch1_energy = Enum.at(energies, 1)

    # Channel 0 must dominate with high energy
    assert ch0_energy > 40.0
    # Channel 1 (adjacent) should be strongly rejected
    assert ch0_energy / max(ch1_energy, 0.001) > 10.0

    [samples, blocks] = PFB.get_telemetry(pfb)
    assert samples == 512
    assert blocks == div(512, num_channels)
  end

  test "channelizes tone at Channel 3 in a 16-channel filterbank" do
    num_channels = 16
    pfb = PFB.new(num_channels, taps_per_branch: 8, window: :blackman_harris)

    target_ch = 3
    iq = Multicarrier.generate_channel_tone(target_ch, num_channels, 1024, amplitude: 90.0)

    channels = PFB.channelize(pfb, iq)
    assert length(channels) == num_channels

    energies = Enum.map(channels, &Multicarrier.measure_energy/1)
    target_energy = Enum.at(energies, target_ch)
    other_energies = List.delete_at(energies, target_ch)

    assert target_energy > 40.0
    max_other = Enum.max(other_energies)

    # Target channel must have substantially greater energy than other bins
    assert target_energy / max(max_other, 0.001) > 8.0
  end
end
