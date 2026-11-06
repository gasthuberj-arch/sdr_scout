defmodule Mix.Tasks.SdrScout.Tui do
  @shortdoc "Starts the interactive real-time SDR Scout terminal dashboard"
  @moduledoc """
  Launches the SDR Scout live terminal dashboard with real-time ADS-B radar,
  APRS packet communication monitoring, RF spectrum waterfall, and native DSP engine telemetry.

  ## Usage

      mix sdr_scout.tui [options]

  ## Options

      --refresh MS      Screen refresh interval in milliseconds (default: 100)
      --no-feeder       Disable synthetic aircraft & APRS background simulation
  """
  use Mix.Task
  alias SdrScout.TUI
  alias SdrScout.Synth.TUIFeeder
  alias SdrScout.TUI.Renderer

  @impl Mix.Task
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args,
        switches: [refresh: :integer, no_feeder: :boolean],
        aliases: [r: :refresh]
      )

    Mix.Task.run("app.start")

    refresh_ms = Keyword.get(opts, :refresh, 100)
    no_feeder? = Keyword.get(opts, :no_feeder, false)

    {:ok, _tui_pid} = TUI.start_link(refresh_interval_ms: refresh_ms, interactive?: true)

    feeder_pid =
      unless no_feeder? do
        {:ok, pid} = TUIFeeder.start_link()
        pid
      end

    # Trap interrupts for graceful teardown
    System.trap_signal(:sigint, fn ->
      cleanup(feeder_pid)
      exit(:normal)
    end)

    listen_keyboard_loop(feeder_pid)
  end

  defp listen_keyboard_loop(feeder_pid) do
    case IO.getn("", 1) do
      "q" ->
        cleanup(feeder_pid)
        :ok

      "Q" ->
        cleanup(feeder_pid)
        :ok

      " " ->
        TUI.toggle_pause()
        listen_keyboard_loop(feeder_pid)

      "c" ->
        if GenServer.whereis(SdrScout.Airspace) do
          GenServer.call(
            SdrScout.Airspace,
            {:evict_stale, [now: System.monotonic_time(:millisecond) + 1_000_000]}
          )
        end

        listen_keyboard_loop(feeder_pid)

      _other ->
        listen_keyboard_loop(feeder_pid)
    end
  end

  defp cleanup(feeder_pid) do
    if feeder_pid && Process.alive?(feeder_pid), do: Process.exit(feeder_pid, :shutdown)
    TUI.stop()
    Renderer.reset_terminal()
  end
end
