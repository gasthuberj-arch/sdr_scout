defmodule SdrScout.Airspace do
  @moduledoc """
  Deterministic Airspace Tracking and Kinematics Engine.

  Manages tracked aircraft state, kinematics, and contact eviction through a deep interface:
  - Pure state transitions: `new/1`, `ingest/3`, `evict_stale/2`, and `snapshot/1`.
  - Process coordination: `start_link/1`, synchronous `ingest/3`, streaming `process_frame/2`,
    and pubsub broadcast via local `Registry` and distributed `:pg`.
  """
  use GenServer
  alias SdrScout.ModeS
  alias SdrScout.Aircraft

  @pubsub_registry SdrScout.Airspace.PubSub
  @pg_group :sdr_scout_airspace
  @default_stale_timeout_ms 60_000
  @eviction_interval_ms 5_000

  defstruct [
    aircraft: %{},
    stale_timeout_ms: @default_stale_timeout_ms,
    schedule_eviction: true
  ]

  # ===========================================================================
  # Pure Functional API
  # ===========================================================================

  @doc """
  Initializes a fresh, empty `%Airspace{}` state struct.
  """
  def new(opts \\ []) do
    %__MODULE__{
      aircraft: %{},
      stale_timeout_ms: Keyword.get(opts, :stale_timeout_ms, @default_stale_timeout_ms),
      schedule_eviction: Keyword.get(opts, :schedule_eviction, true)
    }
  end

  @doc """
  Ingests a 14-byte Mode-S frame into an `%Airspace{}` state struct or a running server.
  Deterministically updates kinematic state (callsign, velocity, or CPR position).

  When passed an `%Airspace{}` struct:
    Returns `{:ok, updated_aircraft, new_airspace}` or `{:error, reason, airspace}`.

  When passed a server reference (PID or name):
    Calls the process synchronously and returns `{:ok, updated_aircraft, snapshot}` or `{:error, reason}`.
  """
  def ingest(airspace_or_server, frame, opts \\ [])

  def ingest(%__MODULE__{} = airspace, frame, opts) when is_binary(frame) do
    case ModeS.decode(frame) do
      {:ok, decoded} ->
        now = Keyword.get(opts, :now, System.monotonic_time(:millisecond))
        icao = decoded.icao
        existing = Map.get(airspace.aircraft, icao, Aircraft.new(icao, decoded.icao_hex, now))
        updated = update_aircraft(existing, decoded, now)

        new_airspace = %{airspace | aircraft: Map.put(airspace.aircraft, icao, updated)}
        {:ok, updated, new_airspace}

      {:error, reason} ->
        {:error, reason, airspace}
    end
  end

  def ingest(server, frame, opts) when is_binary(frame) do
    GenServer.call(server, {:ingest, frame, opts})
  end

  @doc """
  Evicts stale aircraft contacts whose last seen timestamp is before the cutoff.

  When passed an `%Airspace{}` struct:
    Returns `{evicted_icaos, new_airspace}`.

  When passed a server reference:
    Synchronously triggers eviction and returns `{:ok, evicted_icaos, snapshot}`.
  """
  def evict_stale(airspace_or_server, opts \\ [])

  def evict_stale(%__MODULE__{} = airspace, opts) do
    now = Keyword.get(opts, :now, System.monotonic_time(:millisecond))
    cutoff = Keyword.get(opts, :cutoff, now - airspace.stale_timeout_ms)

    {active, evicted} =
      Enum.split_with(airspace.aircraft, fn {_icao, ac} ->
        ac.last_seen >= cutoff
      end)

    evicted_icaos = for {icao, _} <- evicted, do: icao
    new_airspace = %{airspace | aircraft: Map.new(active)}

    {evicted_icaos, new_airspace}
  end

  def evict_stale(server, opts) do
    GenServer.call(server, {:evict_stale, opts})
  end

  @doc """
  Returns a snapshot map of all currently active aircraft.
  Accepts an `%Airspace{}` struct or a server reference (defaults to `__MODULE__`).
  """
  def snapshot(airspace_or_server \\ __MODULE__)

  def snapshot(%__MODULE__{aircraft: ac}), do: ac

  def snapshot(server) do
    GenServer.call(server, :snapshot)
  end

  @doc """
  Backwards-compatible alias for `snapshot/1`.
  """
  def get_airspace(airspace_or_server \\ __MODULE__) do
    snapshot(airspace_or_server)
  end

  # ===========================================================================
  # Process Streaming API
  # ===========================================================================

  @doc """
  Starts a supervised `Airspace` tracking GenServer process.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Asynchronously casts a raw 14-byte Mode-S frame for ingestion.
  Accepts `process_frame(frame)` targeting `__MODULE__` or `process_frame(server, frame)`.
  """
  def process_frame(server_or_frame, frame \\ nil)

  def process_frame(frame, nil) when is_binary(frame) do
    process_frame(__MODULE__, frame)
  end

  def process_frame(server, frame) when is_binary(frame) do
    GenServer.cast(server, {:process_frame, frame})
  end

  @doc """
  Subscribes the calling process to real-time airspace updates.
  """
  def subscribe(registry \\ @pubsub_registry) do
    Registry.register(registry, "airspace", [])
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    # Join distributed :pg group if available
    try do
      :pg.join(@pg_group, self())
    catch
      _, _ -> :ok
    end

    state = new(opts)

    if state.schedule_eviction do
      schedule_eviction()
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, state.aircraft, state}
  end

  @impl true
  def handle_call(:get_airspace, _from, state) do
    {:reply, state.aircraft, state}
  end

  @impl true
  def handle_call({:ingest, frame, opts}, _from, state) do
    case ingest(state, frame, opts) do
      {:ok, updated, new_state} ->
        broadcast({:aircraft_updated, updated})
        {:reply, {:ok, updated, new_state.aircraft}, new_state}

      {:error, reason, _} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:evict_stale, opts}, _from, state) do
    {evicted, new_state} = evict_stale(state, opts)

    for icao <- evicted do
      broadcast({:aircraft_evicted, icao})
    end

    {:reply, {:ok, evicted, new_state.aircraft}, new_state}
  end

  @impl true
  def handle_cast({:process_frame, frame}, state) do
    case ingest(state, frame, []) do
      {:ok, updated, new_state} ->
        broadcast({:aircraft_updated, updated})
        {:noreply, new_state}

      {:error, _, _} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:evict_stale, state) do
    {evicted, new_state} = evict_stale(state, [])

    for icao <- evicted do
      broadcast({:aircraft_evicted, icao})
    end

    if new_state.schedule_eviction do
      schedule_eviction()
    end

    {:noreply, new_state}
  end

  # ===========================================================================
  # Internal Kinematic Calculations
  # ===========================================================================

  defp update_aircraft(ac, decoded, timestamp) do
    ac
    |> Map.update!(:message_count, &(&1 + 1))
    |> Map.put(:last_seen, timestamp)
    |> apply_kinematics(decoded, timestamp)
  end

  defp apply_kinematics(ac, %{type: :identification, callsign: cs}, _time) do
    %{ac | callsign: cs}
  end

  defp apply_kinematics(
         ac,
         %{type: :airborne_velocity, speed: spd, heading: hdg, vertical_rate: vr},
         _time
       ) do
    %{ac | speed: spd, heading: hdg, vertical_rate: vr}
  end

  defp apply_kinematics(
         ac,
         %{
           type: :airborne_position,
           altitude: alt,
           cpr_format: fmt,
           lat_cpr: lat_cpr,
           lon_cpr: lon_cpr
         },
         time
       ) do
    cpr_report = %{lat_cpr: lat_cpr, lon_cpr: lon_cpr, time: time}
    ac = %{ac | altitude: alt}

    ac =
      case fmt do
        :even -> %{ac | cpr_even: cpr_report}
        :odd -> %{ac | cpr_odd: cpr_report}
      end

    if ac.cpr_even != nil and ac.cpr_odd != nil do
      case ModeS.resolve_position(ac.cpr_even, ac.cpr_odd) do
        {:ok, {lat, lon}} ->
          %{ac | latitude: lat, longitude: lon}

        {:error, _} ->
          ac
      end
    else
      ac
    end
  end

  defp apply_kinematics(ac, _other, _time), do: ac

  defp schedule_eviction do
    Process.send_after(self(), :evict_stale, @eviction_interval_ms)
  end

  defp broadcast(event) do
    Registry.dispatch(@pubsub_registry, "airspace", fn entries ->
      for {pid, _} <- entries, do: send(pid, event)
    end)

    try do
      for pid <- :pg.get_members(@pg_group), pid != self() do
        send(pid, event)
      end
    catch
      _, _ -> :ok
    end
  end
end
