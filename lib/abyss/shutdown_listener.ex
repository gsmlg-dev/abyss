defmodule Abyss.ShutdownListener do
  @moduledoc false

  # Used as part of the `Abyss.Server` supervision tree to facilitate
  # stopping the server's listener process early in the shutdown process, in order
  # to allow existing connections to drain without accepting new ones

  use GenServer

  @type state :: %{
          optional(:server_pid) => pid(),
          optional(:listener_pool_pid) => pid() | nil
        }

  @doc false
  @spec start_link(pid()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(server_pid) do
    GenServer.start_link(__MODULE__, server_pid)
  end

  @doc false
  @impl true
  @spec init(pid()) :: {:ok, state, {:continue, :setup_listener_pool_pid}}
  def init(server_pid) do
    Process.flag(:trap_exit, true)
    {:ok, %{server_pid: server_pid}, {:continue, :setup_listener_pool_pid}}
  end

  @doc false
  @impl true
  @spec handle_continue(:setup_listener_pool_pid, state) :: {:noreply, state}
  def handle_continue(:setup_listener_pool_pid, %{server_pid: server_pid} = state) do
    listener_pool_pid = Abyss.Server.listener_pool_pid(server_pid)
    {:noreply, state |> Map.put(:listener_pool_pid, listener_pool_pid)}
  end

  @doc false
  @impl true
  @spec terminate(reason, state) :: :ok
        when reason: :normal | :shutdown | {:shutdown, term} | term
  def terminate(_reason, %{listener_pool_pid: listener_pool_pid}) do
    Abyss.ListenerPool.suspend(listener_pool_pid)
  end

  def terminate(_reason, _state), do: :ok
end
