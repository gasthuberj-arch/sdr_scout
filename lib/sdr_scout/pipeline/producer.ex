defmodule SdrScout.Pipeline.Producer do
  @moduledoc """
  GenStage Producer for raw I/Q chunks.
  Supports:
  - `:benchmark` mode: drains chunks unthrottled to measure peak DSP throughput.
  - `:realtime` mode: paces chunks at 2.0 MSPS (32.768 ms per 64 KB chunk).
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
      timer_active: false
    }

    {:producer, state}
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    new_demand = state.demand + incoming_demand
    dispatch(%{state | demand: new_demand})
  end

  @impl true
  def handle_info(:tick, state) do
    dispatch(%{state | timer_active: false})
  end

  defp dispatch(%{demand: demand} = state) when demand <= 0 do
    {:noreply, [], state}
  end

  defp dispatch(%{chunks: [chunk | rest], demand: demand, mode: :benchmark} = state) do
    {:noreply, [chunk], %{state | chunks: rest, demand: demand - 1}}
  end

  defp dispatch(
         %{chunks: [chunk | rest], demand: demand, mode: :realtime, timer_active: false} = state
       ) do
    Process.send_after(self(), :tick, @chunk_interval_ms)
    {:noreply, [chunk], %{state | chunks: rest, demand: demand - 1, timer_active: true}}
  end

  defp dispatch(%{chunks: [], source_fun: fun, demand: _demand} = state)
       when is_function(fun, 0) do
    case fun.() do
      :eof ->
        {:stop, :normal, state}

      chunk when is_binary(chunk) ->
        dispatch(%{state | chunks: [chunk]})
    end
  end

  defp dispatch(%{chunks: []} = state) do
    {:noreply, [], state}
  end

  defp dispatch(state) do
    {:noreply, [], state}
  end
end
