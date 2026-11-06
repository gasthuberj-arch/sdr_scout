defmodule SdrScout.Pipeline do
  @moduledoc """
  Unified execution pipeline for high-throughput SDR digital signal processing.

  Encapsulates GenStage backpressure, Zig SIMD DSP NIF lifecycle, and frame dispatch.
  Presents a deep interface:
  - `run/2`: Synchronous, deterministic batch processing for tests and benchmarks (zero sleep).
  - `start_link/1`: Supervised streaming pipeline for realtime feeds or background SDR pipelines.
  - `drain/2`: Deterministically flushes all queued chunks through the DSP NIF.
  - `get_telemetry/1` & `telemetry/1`: Queries DSP performance counters.
  - `stop/2`: Clean pipeline shutdown.
  """
  use GenServer
  alias SdrScout.Pipeline.{Producer, DetectorConsumer}

  # ===========================================================================
  # Client API
  # ===========================================================================

  @doc """
  Starts a supervised pipeline consisting of linked Producer and DetectorConsumer stages.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Synchronously runs a list of 64 KB chunks through the DSP pipeline.
  Deterministically awaits complete processing and returns `{:ok, frames, telemetry}`.
  """
  def run(chunks, opts \\ []) when is_list(chunks) do
    caller = self()
    collect? = Keyword.get(opts, :collect_frames, true)
    collector = if collect?, do: caller, else: nil

    pipeline_opts =
      opts
      |> Keyword.put(:mode, :benchmark)
      |> Keyword.put(:chunks, chunks)
      |> Keyword.put(:collector, collector)

    {:ok, pipeline} = start_link(pipeline_opts)

    timeout = Keyword.get(opts, :timeout, 10_000)
    :ok = drain(pipeline, timeout)

    telemetry = get_telemetry(pipeline)

    frames =
      if collect? do
        drain_collected_frames([])
      else
        []
      end

    stop(pipeline)
    {:ok, frames, telemetry}
  end

  @doc """
  Flushes all queued chunks in the pipeline and awaits complete DSP processing.
  """
  def drain(pipeline, timeout \\ 5000) do
    GenServer.call(pipeline, {:drain, timeout}, timeout + 1000)
  end

  @doc """
  Returns raw DSP telemetry `[samples, preambles, crc_ok, fixed]`.
  """
  def get_telemetry(pipeline) do
    GenServer.call(pipeline, :get_telemetry)
  end

  @doc """
  Returns a structured telemetry map.
  """
  def telemetry(pipeline) do
    [samples, preambles, crc_ok, fixed] = get_telemetry(pipeline)

    %{
      samples_processed: samples,
      preambles_detected: preambles,
      crc_valid: crc_ok,
      single_bit_recovered: fixed
    }
  end

  @doc """
  Returns internal PIDs `%{producer: pid, consumer: pid}`.
  """
  def get_pids(pipeline) do
    GenServer.call(pipeline, :get_pids)
  end

  @doc """
  Stops the pipeline.
  """
  def stop(pipeline, reason \\ :normal, timeout \\ 5000) do
    GenServer.stop(pipeline, reason, timeout)
  end

  # ===========================================================================
  # Server Callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    producer_opts = Keyword.take(opts, [:mode, :chunks, :source_fun])
    {:ok, producer} = Producer.start_link(producer_opts)

    consumer_opts =
      opts
      |> Keyword.take([:airspace, :collector])
      |> Keyword.put(:producer, producer)

    {:ok, consumer} = DetectorConsumer.start_link(consumer_opts)

    {:ok, %{producer: producer, consumer: consumer}}
  end

  @impl true
  def handle_call({:drain, timeout}, _from, state) do
    with :ok <- Producer.drain(state.producer, timeout),
         :ok <- DetectorConsumer.sync(state.consumer, timeout) do
      {:reply, :ok, state}
    else
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_telemetry, _from, state) do
    telemetry = DetectorConsumer.get_telemetry(state.consumer)
    {:reply, telemetry, state}
  end

  @impl true
  def handle_call(:get_pids, _from, state) do
    {:reply, %{producer: state.producer, consumer: state.consumer}, state}
  end

  @impl true
  def terminate(_reason, %{producer: p, consumer: c}) do
    for pid <- [p, c] do
      if is_pid(pid) and Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end

    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp drain_collected_frames(acc) do
    receive do
      {:frame, frame} ->
        drain_collected_frames([frame | acc])
    after
      0 ->
        Enum.reverse(acc)
    end
  end
end
