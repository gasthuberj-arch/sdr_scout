defmodule SdrScout.Synth.Scenario do
  @moduledoc """
  Generates multi-aircraft realistic flight trajectories and packages their ADS-B
  messages into 64 KB (65,536-byte) raw I/Q chunks, deliberately straddling chunk boundaries.
  """
  import Bitwise
  alias SdrScout.ModeS.{CRC, CPR}
  alias SdrScout.Synth.Modulator

  @chunk_size 65_536

  @doc """
  Constructs a synthetic 14-byte frame for an aircraft callsign.
  """
  def make_identification_frame(icao, callsign) do
    padded = String.pad_trailing(String.upcase(callsign), 8, " ")

    chars =
      for <<char <- padded>> do
        encode_ais_char(char)
      end

    [c1, c2, c3, c4, c5, c6, c7, c8] = chars
    tc = 4
    cat = 1

    payload = <<17::5, 5::3, icao::24, tc::5, cat::3, c1::6, c2::6, c3::6, c4::6, c5::6, c6::6, c7::6, c8::6>>
    CRC.encode(payload)
  end

  @doc """
  Constructs a synthetic 14-byte frame for airborne position (even or odd CPR).
  """
  def make_airborne_pos_frame(icao, alt_ft, lat, lon, format) do
    tc = 11
    # Q-bit = 1: alt = N * 25 - 1000 => N = (alt + 1000) / 25
    n = round((alt_ft + 1000) / 25)
    # 12-bit encoding with Q-bit in bit 4 (0-indexed from right): upper 7 bits, Q-bit (1), lower 4 bits
    alt_raw = ((n >>> 4) <<< 5) ||| (1 <<< 4) ||| band(n, 0x0F)

    cpr = CPR.encode(lat, lon)

    {cpr_flag, lat_cpr, lon_cpr} =
      case format do
        :even ->
          {0, elem(cpr.even, 0), elem(cpr.even, 1)}
        :odd ->
          {1, elem(cpr.odd, 0), elem(cpr.odd, 1)}
      end

    payload = <<17::5, 5::3, icao::24, tc::5, 0::2, 0::1, alt_raw::12, 0::1, cpr_flag::1, lat_cpr::17, lon_cpr::17>>
    CRC.encode(payload)
  end

  @doc """
  Constructs a synthetic 14-byte frame for airborne velocity.
  """
  def make_airborne_velocity_frame(icao, speed_knots, heading_deg, vertical_rate_fpm) do
    tc = 19
    subtype = 1

    rad = heading_deg * :math.pi() / 180.0
    v_ew = speed_knots * :math.sin(rad)
    v_ns = speed_knots * :math.cos(rad)

    s_ew = if v_ew < 0, do: 1, else: 0
    v_ew_raw = round(abs(v_ew)) + 1

    s_ns = if v_ns < 0, do: 1, else: 0
    v_ns_raw = round(abs(v_ns)) + 1

    s_vr = if vertical_rate_fpm < 0, do: 1, else: 0
    vr_raw = if vertical_rate_fpm != 0, do: round(abs(vertical_rate_fpm) / 64) + 1, else: 0

    # Subtype 1 payload: 56 bits total for ME
    # TC (5) + Subtype (3) + IC (1) + IFR (1) + NAC (3) +
    # s_ew (1) + v_ew (10) + s_ns (1) + v_ns (10) +
    # vr_src (1) + s_vr (1) + vr (9) + tail (10) = 56 bits
    # 5 + 3 + 24 + 56 = 88 bits (11 bytes)
    payload =
      <<17::5, 5::3, icao::24, tc::5, subtype::3, 0::1, 1::1, 1::3,
        s_ew::1, v_ew_raw::10, s_ns::1, v_ns_raw::10,
        0::1, s_vr::1, vr_raw::9, 0::10>>
    CRC.encode(payload)
  end

  @doc """
  Generates a scenario of `num_chunks` 64 KB blocks with realistic aircraft transmissions.
  Returns a list of 64 KB binaries.
  """
  def generate_stream(opts \\ []) do
    num_chunks = Keyword.get(opts, :num_chunks, 3)

    # Simulated flights
    flights = [
      %{icao: 0x4840D6, callsign: "KLM1023", lat: 52.3676, lon: 4.9041, alt: 32000, speed: 450, heading: 90.0, vr: 0},
      %{icao: 0x40621D, callsign: "BAW456", lat: 51.4700, lon: -0.4543, alt: 18000, speed: 380, heading: 120.0, vr: -1200},
      %{icao: 0x3C6444, callsign: "DLH789", lat: 50.0379, lon: 8.5622, alt: 24000, speed: 410, heading: 240.0, vr: 800}
    ]

    # Generate sequence of modulated frames with quiet/noise gaps in between
    # Deliberately place one frame exactly across the 65,536 boundary (e.g. at offset 65,400)
    # 480 bytes per frame
    frames =
      Enum.flat_map(flights, fn f ->
        [
          make_identification_frame(f.icao, f.callsign),
          make_airborne_pos_frame(f.icao, f.alt, f.lat, f.lon, :even),
          make_airborne_pos_frame(f.icao, f.alt, f.lat, f.lon, :odd),
          make_airborne_velocity_frame(f.icao, f.speed, f.heading, f.vr)
        ]
      end)

    total_bytes = num_chunks * @chunk_size
    # Create empty noise buffer
    noise = Modulator.generate_noise(div(total_bytes, 2))

    # Splice modulated frames into noise at deliberate offsets
    # Offset 65,400 will span across chunk 1 (ends at 65,536) and chunk 2
    offsets = [
      5_000,
      25_000,
      45_000,
      65_400, # Straddles chunk 1 and 2!
      80_000,
      110_000,
      131_000, # Straddles chunk 2 and 3!
      150_000
    ]

    buffer =
      Enum.zip(frames, Stream.cycle(offsets))
      |> Enum.reduce(noise, fn {frame, offset}, acc ->
        iq_sig = Modulator.modulate_frame(frame)
        splice_binary(acc, iq_sig, offset)
      end)

    # Chunk into 64 KB pieces
    for <<chunk::binary-size(@chunk_size) <- buffer>>, do: chunk
  end

  defp splice_binary(target, insert, offset) do
    len = byte_size(insert)
    <<head::binary-size(^offset), _replaced::binary-size(^len), tail::binary>> = target
    head <> insert <> tail
  end

  defp encode_ais_char(char) when char in ?A..?Z, do: char - ?A + 1
  defp encode_ais_char(char) when char in ?0..?9, do: char - ?0 + 48
  defp encode_ais_char(?\s), do: 32
  defp encode_ais_char(_), do: 32
end
