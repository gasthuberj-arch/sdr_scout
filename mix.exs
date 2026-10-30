defmodule SdrScout.MixProject do
  use Mix.Project

  def project do
    [
      app: :sdr_scout,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {SdrScout.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:zigler, "~> 0.17.0", runtime: false},
      {:gen_stage, "~> 1.3"}
    ]
  end
end
