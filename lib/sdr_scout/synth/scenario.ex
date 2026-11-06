defmodule SdrScout.Synth.Scenario do
  @moduledoc """
  Generates multi-aircraft realistic flight trajectories and packages their ADS-B
  messages into 64 KB (65,536-byte) raw I/Q chunks, deliberately straddling chunk boundaries.
  """
  alias SdrScout.ModeS
  alias SdrScout.Synth.Modulator

  @chunk_size 65_536

  @doc """
  Constructs a synthetic 14-byte frame for an aircraft callsign.
  """
  def make_identification_frame(icao, callsign) do
    ModeS.encode(:identification, icao, callsign)
  end

  @doc """
  Constructs a synthetic 14-byte frame for airborne position (even or odd CPR).
  """
  def make_airborne_pos_frame(icao, alt_ft, lat, lon, format) do
    ModeS.encode(:airborne_position, icao, alt_ft, lat, lon, format)
  end

  @doc """
  Constructs a synthetic 14-byte frame for airborne velocity.
  """
  def make_airborne_velocity_frame(icao, speed_knots, heading_deg, vertical_rate_fpm) do
    ModeS.encode(:airborne_velocity, icao, speed_knots, heading_deg, vertical_rate_fpm)
  end

  @doc """
  Generates a scenario of `num_chunks` 64 KB blocks with realistic aircraft transmissions.
  Returns a list of 64 KB binaries.
  """
  def generate_stream(opts \\ []) do
    num_chunks = Keyword.get(opts, :num_chunks, 3)

    # Simulated flights
    flights = [
      %{
        icao: 0x4840D6,
        callsign: "KLM1023",
        lat: 52.3676,
        lon: 4.9041,
        alt: 32000,
        speed: 450,
        heading: 90.0,
        vr: 0
      },
      %{
        icao: 0x40621D,
        callsign: "BAW456",
        lat: 51.4700,
        lon: -0.4543,
        alt: 18000,
        speed: 380,
        heading: 120.0,
        vr: -1200
      },
      %{
        icao: 0x3C6444,
        callsign: "DLH789",
        lat: 50.0379,
        lon: 8.5622,
        alt: 24000,
        speed: 410,
        heading: 240.0,
        vr: 800
      }
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
      # Straddles chunk 1 and 2!
      65_400,
      80_000,
      110_000,
      # Straddles chunk 2 and 3!
      131_000,
      150_000
    ]

    valid_offsets = Enum.filter(offsets, fn off -> off + 480 <= total_bytes end)

    offsets_stream =
      if valid_offsets != [] do
        Stream.cycle(valid_offsets)
      else
        Stream.cycle([0])
      end

    buffer =
      Enum.zip(frames, offsets_stream)
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
end
