defmodule SdrScout.Airspace do
  @moduledoc """
  Cluster-ready state manager for all tracked aircraft in the monitored airspace.
  Features:
  - Tracks aircraft by 24-bit ICAO address via `SdrScout.Aircraft`
  - Periodically evicts stale aircraft after configurable timeout (default: 60s)
  - Broadcasts updates and evictions via local `Registry` and distributed `:pg`
  """
  use GenServer
  alias SdrScout.ModeS
  alias SdrScout.Aircraft

  @pubsub_registry SdrScout.Airspace.PubSub
  @pg_group :sdr_scout_airspace
  @default_stale_timeout_ms 60_000
  @eviction_interval_ms 5_000

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Processes a raw 14-byte Mode-S frame.
  """
  def process_frame(frame) do
    GenServer.cast(__MODULE__, {:process_frame, frame})
  end

  @doc """
  Returns a snapshot map of all currently active aircraft.
  """
  def get_airspace do
    GenServer.call(__MODULE__, :get_airspace)
  end

  @doc """
  Subscribes the calling process to real-time airspace updates.
  """
  def subscribe do
    Registry.register(@pubsub_registry, "airspace", [])
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    # Join distributed :pg group if available
    try do
      :pg.join(@pg_group, self())
    catch
      _, _ -> :ok
    end

    stale_timeout = Keyword.get(opts, :stale_timeout_ms, @default_stale_timeout_ms)
    schedule_eviction()

    {:ok, %{aircraft: %{}, stale_timeout_ms: stale_timeout}}
  end

  @impl true
  def handle_call(:get_airspace, _from, state) do
    {:reply, state.aircraft, state}
  end

  @impl true
  def handle_cast({:process_frame, frame}, state) do
    case ModeS.decode(frame) do
      {:ok, decoded} ->
        now = System.monotonic_time(:millisecond)
        icao = decoded.icao
        existing = Map.get(state.aircraft, icao, Aircraft.new(icao, decoded.icao_hex))
        updated = Aircraft.apply_message(existing, decoded, now)

        broadcast({:aircraft_updated, updated})
        {:noreply, %{state | aircraft: Map.put(state.aircraft, icao, updated)}}

      {:error, _} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:evict_stale, state) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - state.stale_timeout_ms

    {active, evicted} =
      Enum.split_with(state.aircraft, fn {_icao, ac} ->
        ac.last_seen >= cutoff
      end)

    for {icao, _} <- evicted do
      broadcast({:aircraft_evicted, icao})
    end

    schedule_eviction()
    {:noreply, %{state | aircraft: Map.new(active)}}
  end

  defp schedule_eviction do
    Process.send_after(self(), :evict_stale, @eviction_interval_ms)
  end

  defp broadcast(event) do
    # 1. Local Registry
    Registry.dispatch(@pubsub_registry, "airspace", fn entries ->
      for {pid, _} <- entries, do: send(pid, event)
    end)

    # 2. Distributed :pg group
    try do
      for pid <- :pg.get_members(@pg_group), pid != self() do
        send(pid, event)
      end
    catch
      _, _ -> :ok
    end
  end
end
