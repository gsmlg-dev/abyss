defmodule Abyss.Pool do
  use Supervisor

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    poolboy_config = [
      name: {:local, :udp_worker_pool},
      worker_module: Abyss.Worker,
      # Number of workers in the pool
      size: 5,
      # Extra workers if needed
      max_overflow: 2
    ]

    children = [
      :poolboy.child_spec(:udp_worker_pool, poolboy_config)
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
