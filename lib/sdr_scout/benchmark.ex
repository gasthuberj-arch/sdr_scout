defmodule SdrScout.Benchmark do
  @moduledoc """
  Throughput benchmark runner for the Zig SIMD DSP NIF and GenStage pipeline.
  Measures processing speed in Mega-samples per second (MSPS) and MB/s.
  """
  alias SdrScout.Synth.Scenario
  alias SdrScout.Native.Dsp
  alias SdrScout.Pipeline.{Producer, DetectorConsumer}

  @doc """
  Runs an unthrottled raw Zig SIMD NIF benchmark across `num_chunks` (default: 50).
  """
  def run_nif(num_chunks \\ 50) do
    chunks = Scenario.generate_stream(num_chunks: num_chunks)
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
    chunks = Scenario.generate_stream(num_chunks: num_chunks)
    total_samples = num_chunks * 32_768

    test_pid = self()

    {:ok, producer} = Producer.start_link(mode: :benchmark, chunks: chunks)
    {:ok, consumer} = DetectorConsumer.start_link(producer: producer, airspace: test_pid)

    t0 = System.monotonic_time(:microsecond)

    # Wait until all chunks are drained
    wait_drain(producer)

    t1 = System.monotonic_time(:microsecond)
    elapsed_s = (t1 - t0) / 1_000_000.0
    msps = total_samples / elapsed_s / 1_000_000.0

    [samples, preambles, crc_ok, fixed] = GenServer.call(consumer, :get_telemetry)

    %{
      pipeline_msps: Float.round(msps, 2),
      elapsed_seconds: Float.round(elapsed_s, 4),
      samples_processed: samples,
      preambles_detected: preambles,
      crc_valid: crc_ok,
      single_bit_recovered: fixed
    }
  end

  defp wait_drain(producer) do
    case :sys.get_state(producer) do
      %GenStage{state: %{chunks: []}} ->
        Process.sleep(50)
        :ok

      %{chunks: []} ->
        Process.sleep(50)
        :ok

      _ ->
        Process.sleep(10)
        wait_drain(producer)
    end
  end
end
