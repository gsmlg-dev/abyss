defmodule Abyss.Server do
  @moduledoc false

  use Supervisor

  @spec start_link(Abyss.ServerConfig.t()) :: Supervisor.on_start()
  def start_link(%Abyss.ServerConfig{} = config) do
    Supervisor.start_link(__MODULE__, config, config.supervisor_options)
  end

  def resume(supervisor) do
    listener_pool_pid(supervisor)
    |> Abyss.ListenerPool.resume()
  end

  def suspend(supervisor) do
    listener_pool_pid(supervisor)
    |> Abyss.ListenerPool.suspend()
  end

  @spec listener_pool_pid(Supervisor.supervisor()) :: pid() | nil
  def listener_pool_pid(supervisor) do
    supervisor
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {:listener_pool, listener_pool_pid, _, _} when is_pid(listener_pool_pid) ->
        listener_pool_pid

      _ ->
        false
    end)
  end

  @spec connection_sup_pid(Supervisor.supervisor()) :: pid() | nil
  def connection_sup_pid(supervisor) do
    supervisor
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {:connection_sup, connection_sup_pid, _, _} when is_pid(connection_sup_pid) ->
        connection_sup_pid

      _ ->
        false
    end)
  end

  @impl Supervisor
  @spec init(Abyss.ServerConfig.t()) ::
          {:ok,
           {Supervisor.sup_flags(),
            [Supervisor.child_spec() | (old_erlang_child_spec :: :supervisor.child_spec())]}}
  def init(config) do
    server_pid = self()
    children = [
      {Abyss.ListenerPool, {server_pid, config}}
      |> Supervisor.child_spec(id: :listener_pool),
      # {Abyss.SenderPool, {server_pid, config}}
      # |> Supervisor.child_spec(id: :sender_pool),
      {DynamicSupervisor, strategy: :one_for_one, max_children: config.num_connections}
      |> Supervisor.child_spec(id: :connection_sup),
      Supervisor.child_spec(
        {Task,
         fn ->
           server_pid
           |> Abyss.Server.listener_pool_pid()
           |> Abyss.ListenerPool.start_listening()
         end},
        id: :activator
      ),
      # {Abyss.ShutdownListener, server_pid}
      # |> Supervisor.child_spec(id: :shutdown_listener)
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
