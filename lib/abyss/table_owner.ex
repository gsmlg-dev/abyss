defmodule Abyss.TableOwner do
  @moduledoc false
  # Owns the shared named ETS tables used across all Abyss server instances:
  #
  # - `:abyss_listener_info` - listener socket/endpoint cache (see
  #   `Abyss.Listener`)
  # - `:abyss_telemetry_metrics` - metrics counters (see `Abyss.Telemetry`)
  #
  # The tables are public; this process only ties their lifetime to the
  # `:abyss` application. All lazy `ensure_*` calls route table creation
  # through `ensure_table/2` so that no matter which process first needs a
  # table, it is created by (and owned by) this process rather than by a
  # transient server, listener, or handler process.

  use GenServer

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @doc false
  # Ensure a named ETS table exists. When this process is running the table
  # is created here so it survives the caller's death; otherwise (the :abyss
  # application not started) it is created in the calling process as a
  # fallback.
  @spec ensure_table(atom(), list()) :: :ok
  def ensure_table(name, opts) do
    case :ets.whereis(name) do
      :undefined ->
        case Process.whereis(__MODULE__) do
          nil -> create_table(name, opts)
          pid when pid == self() -> create_table(name, opts)
          _pid -> GenServer.call(__MODULE__, {:ensure_table, name, opts})
        end

      _ref ->
        :ok
    end
  end

  @doc false
  def track_scope(scope) when is_pid(scope) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid when pid == self() -> :ok
      _ -> GenServer.call(__MODULE__, {:track_scope, scope})
    end
  end

  def track_scope(_scope), do: :ok

  @doc false
  def monitor_listener(listener) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _ -> GenServer.call(__MODULE__, {:monitor_listener, listener})
    end
  end

  @doc false
  def admission(operation) do
    case Process.whereis(__MODULE__) do
      pid when pid == self() -> Abyss.UDPAdmission.transition(operation)
      nil -> Abyss.UDPAdmission.transition(operation)
      _pid -> GenServer.call(__MODULE__, {:admission, operation})
    end
  end

  @impl GenServer
  def init(_arg) do
    Abyss.Listener.ensure_info_table_exists()
    Abyss.Telemetry.init_metrics()
    {:ok, %{scopes: %{}, listeners: %{}}}
  end

  @impl GenServer
  def handle_call({:ensure_table, name, opts}, _from, state) do
    {:reply, create_table(name, opts), state}
  end

  def handle_call({:admission, operation}, _from, state),
    do: {:reply, Abyss.UDPAdmission.transition(operation), state}

  def handle_call({:track_scope, scope}, _from, state) do
    scopes = Map.put_new_lazy(state.scopes, scope, fn -> Process.monitor(scope) end)
    {:reply, :ok, %{state | scopes: scopes}}
  end

  def handle_call({:monitor_listener, listener}, _from, state) do
    listeners = Map.put_new_lazy(state.listeners, listener, fn -> Process.monitor(listener) end)
    {:reply, :ok, %{state | listeners: listeners}}
  end

  @impl GenServer
  def handle_info({:DOWN, monitor, :process, scope, _reason}, state) do
    case Map.fetch(state.scopes, scope) do
      {:ok, ^monitor} ->
        Abyss.Listener.clear_desired(scope)
        Abyss.Telemetry.clear_scope(scope)
        {:noreply, %{state | scopes: Map.delete(state.scopes, scope)}}

      _ ->
        cleanup_listener(monitor, scope, state)
    end
  end

  defp cleanup_listener(monitor, listener, state) do
    case Map.fetch(state.listeners, listener) do
      {:ok, ^monitor} ->
        Abyss.Listener.cleanup_owner(listener)
        {:noreply, %{state | listeners: Map.delete(state.listeners, listener)}}

      _ ->
        {:noreply, state}
    end
  end

  defp create_table(name, opts) do
    _ = :ets.new(name, opts)
    :ok
  rescue
    # Concurrent creation race - the table already exists
    ArgumentError -> :ok
  end
end
