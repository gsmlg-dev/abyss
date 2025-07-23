defmodule Abyss.ListenerPool do
  @moduledoc false

  use Supervisor

  @spec start_link({server_pid :: pid, Abyss.ServerConfig.t()}) :: Supervisor.on_start()
  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg)
  end

  @spec listener_pids(Supervisor.supervisor()) :: [pid()]
  def listener_pids(supervisor) do
    try do
      case Process.alive?(supervisor) do
        false ->
          []

        true ->
          supervisor
          |> Supervisor.which_children()
          |> Enum.reduce([], fn
            {_, listener_pid, _, _}, acc when is_pid(listener_pid) -> [listener_pid | acc]
            _, acc -> acc
          end)
      end
    rescue
      ArgumentError -> []
      _ -> []
    end
  end

  @spec suspend(Supervisor.supervisor()) :: :ok | :error
  def suspend(pid) do
    try do
      case Process.alive?(pid) do
        false ->
          :error

        true ->
          pid
          |> listener_pids()
          |> Enum.each(&Process.exit(&1, :normal))

          :ok
      end
    rescue
      ArgumentError -> :error
      _ -> :error
    end
  end

  @spec resume(Supervisor.supervisor()) :: :ok | :error
  def resume(pid) do
    try do
      case Process.alive?(pid) do
        false ->
          :error

        true ->
          # Send resume message to all listeners
          pid
          |> listener_pids()
          |> Enum.each(&send(&1, :start_listening))

          :ok
      end
    rescue
      ArgumentError -> :error
      _ -> :error
    end
  end

  def start_listening(pid) do
    pid
    |> listener_pids()
    |> Enum.each(&send(&1, :start_listening))
  end

  @impl Supervisor
  @spec init({server_pid :: pid, Abyss.ServerConfig.t()}) ::
          {:ok,
           {Supervisor.sup_flags(),
            [Supervisor.child_spec() | (old_erlang_child_spec :: :supervisor.child_spec())]}}
  def init(
        {server_pid, %Abyss.ServerConfig{num_listeners: num_listeners, broadcast: false} = config}
      ) do
    1..num_listeners
    |> Enum.map(
      &Supervisor.child_spec({Abyss.Listener, {"listener-#{&1}", server_pid, config}},
        id: "listener-#{&1}"
      )
    )
    |> Supervisor.init(strategy: :one_for_one)
  end

  def init({server_pid, %Abyss.ServerConfig{num_listeners: _, broadcast: true} = config}) do
    [
      Supervisor.child_spec({Abyss.Listener, {"listener-broadcast", server_pid, config}},
        id: "listener-broadcast"
      )
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end
end
