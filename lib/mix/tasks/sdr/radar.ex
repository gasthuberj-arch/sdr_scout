defmodule Mix.Tasks.Sdr.Radar do
  @moduledoc """
  CLI command to launch the live SDR Scout Radar:
      mix sdr.radar [--chunks N] [--realtime]
  """
  use Mix.Task
  alias SdrScout.Synth.Scenario
  alias SdrScout.Pipeline
  alias SdrScout.TUI

  @shortdoc "Runs the live terminal ADS-B radar scope"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [chunks: :integer, realtime: :boolean],
        aliases: [c: :chunks, r: :realtime]
      )

    num_chunks = Keyword.get(opts, :chunks, 100)
    mode = if Keyword.get(opts, :realtime, false), do: :realtime, else: :benchmark

    chunks = Scenario.generate_stream(num_chunks: num_chunks)

    {:ok, pipeline} = Pipeline.start_link(mode: mode, chunks: chunks)

    # Refresh TUI every 200 ms
    loop(pipeline, 15)
    Pipeline.stop(pipeline)
  end

  defp loop(_pipeline, 0), do: :ok

  defp loop(pipeline, iterations) do
    telemetry = Pipeline.get_telemetry(pipeline)
    IO.puts(TUI.render_frame(51.5, 4.0, telemetry))
    Process.sleep(200)
    loop(pipeline, iterations - 1)
  end
end
