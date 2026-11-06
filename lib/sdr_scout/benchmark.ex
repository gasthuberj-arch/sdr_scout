defmodule SdrScout.Benchmark do
  @moduledoc """
  Throughput benchmark runner for the Zig SIMD DSP NIF and GenStage pipeline.
  Measures processing speed in Mega-samples per second (MSPS) and MB/s.
  """
  alias SdrScout.Synth.Scenario
  alias SdrScout.Native.Dsp
  alias SdrScout.Pipeline

  @doc """
  Runs an unthrottled raw Zig SIMD NIF benchmark across `num_chunks` (default: 50).
  Pre-generates a pool of realistic chunks to prevent Elixir heap bloat during high-iteration benchmarks.
  """
  def run_nif(num_chunks \\ 50) do
    base_count = min(num_chunks, 50)
    base_chunks = Scenario.generate_stream(num_chunks: base_count)

    chunks =
      if num_chunks > base_count do
        Stream.cycle(base_chunks) |> Enum.take(num_chunks)
      else
        base_chunks
      end

    total_samples = num_chunks * 32_768
    total_bytes = num_chunks * 65_536

    ctx = Dsp.new_context()

    {time_us, _} =
      :timer.tc(fn ->
        for chunk <- chunks do
          Dsp.process_chunk(ctx, chunk)
        end
      end)

    time_s = time_us / 1_000_000.0
    msps = total_samples / time_s / 1_000_000.0
    mb_s = total_bytes / time_s / 1_000_000.0
    telemetry = Dsp.get_telemetry(ctx)

    %{
      num_chunks: num_chunks,
      total_samples: total_samples,
      total_bytes: total_bytes,
      elapsed_seconds: Float.round(time_s, 4),
      msps: Float.round(msps, 2),
      mb_per_s: Float.round(mb_s, 2),
      realtime_factor: Float.round(msps / 2.0, 1),
      telemetry: telemetry
    }
  end

  @doc """
  Runs an end-to-end GenStage pipeline benchmark.
  """
  def run_pipeline(num_chunks \\ 50) do
    base_count = min(num_chunks, 50)
    base_chunks = Scenario.generate_stream(num_chunks: base_count)

    chunks =
      if num_chunks > base_count do
        Stream.cycle(base_chunks) |> Enum.take(num_chunks)
      else
        base_chunks
      end

    total_samples = num_chunks * 32_768

    test_pid = self()

    t0 = System.monotonic_time(:microsecond)

    {:ok, _frames, [samples, preambles, crc_ok, fixed]} =
      Pipeline.run(chunks, airspace: test_pid)

    t1 = System.monotonic_time(:microsecond)
    elapsed_s = (t1 - t0) / 1_000_000.0
    msps = total_samples / elapsed_s / 1_000_000.0

    %{
      pipeline_msps: Float.round(msps, 2),
      elapsed_seconds: Float.round(elapsed_s, 4),
      samples_processed: samples,
      preambles_detected: preambles,
      crc_valid: crc_ok,
      single_bit_recovered: fixed
    }
  end
end
