defmodule SdrScout.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :duplicate, name: SdrScout.Airspace.PubSub},
      SdrScout.Airspace
    ]

    opts = [strategy: :one_for_one, name: SdrScout.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
