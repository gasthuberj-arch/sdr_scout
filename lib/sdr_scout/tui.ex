defmodule SdrScout.TUI do
  @moduledoc """
  Interactive Terminal Dashboard for SDR Scout.
  Orchestrates real-time rendering of ADS-B radar, APRS communications,
  RF spectrum waterfalls, and native DSP engine telemetry.
  """
  use GenServer
  alias SdrScout.TUI.Renderer
  alias SdrScout.Airspace

  defstruct [
    :timer_ref,
    aircraft: %{},
    aprs_packets: [],
    spectrum_bins: [],
    waterfall_history: [],
    telemetry: %{
      dsp_msps: 48.0,
      mode_s_count: 0,
      crc_rate: 99.8,
      aprs_count: 0,
      single_bit_recovered: 0
    },
    paused?: false,
    refresh_interval_ms: 100
  ]

  # ===========================================================================
  # Client API
  # ===========================================================================

  @doc """
  Starts the TUI GenServer.
  Options:
    - `:refresh_interval_ms` - Frame tick interval (default: 100ms)
    - `:interactive?` - Whether to initialize terminal alternate screen buffer (default: true)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Stops the TUI and restores terminal settings.
  """
  def stop do
    if GenServer.whereis(__MODULE__) do
      GenServer.stop(__MODULE__)
    end
  end

  @doc """
  Pushes an updated list of power spectrum bins (64 normalized values 0.0 - 1.0).
  """
  def update_spectrum(bins) when is_list(bins) do
    if pid = GenServer.whereis(__MODULE__) do
      GenServer.cast(pid, {:update_spectrum, bins})
    end
  end

  @doc """
  Pushes a decoded APRS frame into the live dashboard feed.
  """
  def push_aprs_packet(pkt) do
    if pid = GenServer.whereis(__MODULE__) do
      GenServer.cast(pid, {:push_aprs, pkt})
    end
  end

  @doc """
  Pushes an updated telemetry metrics map.
  """
  def update_telemetry(metrics) when is_map(metrics) do
    if pid = GenServer.whereis(__MODULE__) do
      GenServer.cast(pid, {:update_telemetry, metrics})
    end
  end

  @doc """
  Pushes an updated map of aircraft contacts.
  """
  def update_aircraft(aircraft_map) when is_map(aircraft_map) do
    if pid = GenServer.whereis(__MODULE__) do
      GenServer.cast(pid, {:update_aircraft, aircraft_map})
    end
  end

  @doc """
  Renders a single dashboard frame to string (legacy radar scope API).
  """
  def render_frame(_center_lat \\ 52.0, _center_lon \\ 5.0, telemetry \\ nil) do
    aircraft_map =
      case GenServer.whereis(Airspace) do
        nil -> %{}
        _pid -> Airspace.snapshot()
      end

    telemetry_map =
      case telemetry do
        %{dsp_msps: _} = map -> map
        _ -> %{dsp_msps: 48.0, mode_s_count: map_size(aircraft_map)}
      end

    dummy_state = %{
      aircraft: aircraft_map,
      aprs_packets: [],
      spectrum_bins: List.duplicate(0.1, 64),
      waterfall_history: [List.duplicate(0.1, 64)],
      telemetry: telemetry_map
    }

    Renderer.render(dummy_state, {90, 24}) |> IO.iodata_to_binary()
  end

  @doc """
  Toggles pause state for the live simulation.
  """
  def toggle_pause do
    if pid = GenServer.whereis(__MODULE__) do
      GenServer.call(pid, :toggle_pause)
    end
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    interactive? = Keyword.get(opts, :interactive?, true)
    refresh_ms = Keyword.get(opts, :refresh_interval_ms, 100)

    if interactive? do
      Renderer.init_terminal()
      # Ensure terminal reset on crash/exit
      System.at_exit(fn _ ->
        Renderer.reset_terminal()
      end)
    end

    # Initialize 64 empty spectrum bins
    initial_bins = List.duplicate(0.05, 64)

    timer_ref = :erlang.send_after(refresh_ms, self(), :tick)

    state = %__MODULE__{
      timer_ref: timer_ref,
      spectrum_bins: initial_bins,
      waterfall_history: [initial_bins, initial_bins, initial_bins, initial_bins],
      refresh_interval_ms: refresh_ms
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:update_spectrum, bins}, state) do
    new_waterfall = [bins | Enum.take(state.waterfall_history, 7)]
    {:noreply, %{state | spectrum_bins: bins, waterfall_history: new_waterfall}}
  end

  @impl true
  def handle_cast({:push_aprs, pkt}, state) do
    new_packets = [pkt | Enum.take(state.aprs_packets, 19)]
    new_telemetry = Map.update(state.telemetry, :aprs_count, 1, &(&1 + 1))
    {:noreply, %{state | aprs_packets: new_packets, telemetry: new_telemetry}}
  end

  @impl true
  def handle_cast({:update_telemetry, metrics}, state) do
    {:noreply, %{state | telemetry: Map.merge(state.telemetry, metrics)}}
  end

  @impl true
  def handle_cast({:update_aircraft, aircraft_map}, state) do
    {:noreply, %{state | aircraft: aircraft_map}}
  end

  @impl true
  def handle_call(:toggle_pause, _from, state) do
    {:reply, not state.paused?, %{state | paused?: not state.paused?}}
  end

  @impl true
  def handle_info(:tick, state) do
    unless state.paused? do
      # Query airspace snapshot if available
      aircraft =
        case GenServer.whereis(Airspace) do
          nil -> state.aircraft
          _pid -> Airspace.snapshot()
        end

      # Get terminal dimensions or fallback to 100x32
      dimensions = get_terminal_dimensions()

      # Render full frame
      frame = Renderer.render(%{state | aircraft: aircraft}, dimensions)
      IO.write(frame)
    end

    timer_ref = :erlang.send_after(state.refresh_interval_ms, self(), :tick)
    {:noreply, %{state | timer_ref: timer_ref}}
  end

  @impl true
  def terminate(_reason, _state) do
    Renderer.reset_terminal()
    :ok
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp get_terminal_dimensions do
    case :io.columns() do
      {:ok, cols} ->
        case :io.rows() do
          {:ok, rows} -> {cols, rows}
          _ -> {cols, 32}
        end

      _ ->
        {100, 32}
    end
  end
end
