defmodule SdrScout.Pipeline.Producer do
  @moduledoc """
  GenStage Producer for raw I/Q chunks.
  Supports:
  - `:benchmark` mode: drains chunks fulfilling batches up to the requested demand.
  - `:realtime` mode: paces chunks at 2.0 MSPS (32.768 ms per 64 KB chunk).
  - Deterministic drain synchronization via `drain/2`.
  """
  use GenStage

  @chunk_size 65_536
  # 2.0 MSPS * 2 bytes/sample
  @bytes_per_second 4_000_000
  # ~16 ms per 64 KB
  @chunk_interval_ms div(@chunk_size * 1000, @bytes_per_second)

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @doc """
  Awaits until all pending chunks have been emitted to consumers.
  """
  def drain(producer, timeout \\ 5000) do
    GenStage.call(producer, :await_drain, timeout)
  end

  @impl true
  def init(opts) do
    mode = Keyword.get(opts, :mode, :benchmark)
    chunks = Keyword.get(opts, :chunks, [])
    source_fun = Keyword.get(opts, :source_fun, nil)

    state = %{
      mode: mode,
      chunks: chunks,
      source_fun: source_fun,
      demand: 0,
      timer_active: false,
      drain_waiters: []
    }

    {:producer, state}
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    new_demand = state.demand + incoming_demand
    dispatch(%{state | demand: new_demand})
  end

  @impl true
  def handle_call(:await_drain, _from, %{chunks: []} = state) do
    {:reply, :ok, [], state}
  end

  @impl true
  def handle_call(:await_drain, from, state) do
    {:noreply, [], %{state | drain_waiters: [from | state.drain_waiters]}}
  end

  @impl true
  def handle_info(:tick, state) do
    dispatch(%{state | timer_active: false})
  end

  defp dispatch(%{demand: demand} = state) when demand <= 0 do
    {:noreply, [], state}
  end

  # Benchmark mode: batch take up to demand chunks
  defp dispatch(%{chunks: chunks, demand: demand, mode: :benchmark} = state) when chunks != [] do
    {to_emit, remaining} = Enum.split(chunks, demand)
    emitted_count = length(to_emit)

    new_state =
      %{state | chunks: remaining, demand: demand - emitted_count}
      |> maybe_reply_drain_waiters()

    {:noreply, to_emit, new_state}
  end

  # Realtime mode: emit one chunk and pace next tick
  defp dispatch(
         %{chunks: [chunk | rest], demand: demand, mode: :realtime, timer_active: false} = state
       ) do
    Process.send_after(self(), :tick, @chunk_interval_ms)

    new_state =
      %{state | chunks: rest, demand: demand - 1, timer_active: true}
      |> maybe_reply_drain_waiters()

    {:noreply, [chunk], new_state}
  end

  defp dispatch(%{chunks: [], source_fun: fun} = state) when is_function(fun, 0) do
    case fun.() do
      :eof ->
        {:stop, :normal, maybe_reply_drain_waiters(state)}

      chunk when is_binary(chunk) ->
        dispatch(%{state | chunks: [chunk]})
    end
  end

  defp dispatch(%{chunks: []} = state) do
    {:noreply, [], maybe_reply_drain_waiters(state)}
  end

  defp dispatch(state) do
    {:noreply, [], state}
  end

  defp maybe_reply_drain_waiters(%{chunks: [], drain_waiters: waiters} = state)
       when is_list(waiters) and waiters != [] do
    for waiter <- waiters, do: GenStage.reply(waiter, :ok)
    %{state | drain_waiters: []}
  end

  defp maybe_reply_drain_waiters(state), do: state
end
