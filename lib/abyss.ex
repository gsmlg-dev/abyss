defmodule Abyss do
  @moduledoc """
  Abyss is a modern, pure Elixir UDP socket server
  """
  @type options :: [
          handler_module: module(),
          handler_options: term(),
          genserver_options: GenServer.options(),
          supervisor_options: [Supervisor.option()],
          port: :inet.port_number(),
          transport_module: module(),
          transport_options: transport_options(),
          num_acceptors: pos_integer(),
          num_connections: non_neg_integer() | :infinity,
          max_connections_retry_count: non_neg_integer(),
          max_connections_retry_wait: timeout(),
          read_timeout: timeout(),
          shutdown_timeout: timeout(),
          silent_terminate_on_error: boolean()
        ]

  @typedoc "A module implementing `Abyss.Transport` behaviour"
  @type transport_module :: Abyss.Transport.UDP

  @typedoc "A keyword list of options to be passed to the transport module's `listen/2` function"
  @type transport_options() :: Abyss.Transport.listen_options()

  @doc false
  @spec child_spec(options()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, make_ref()},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent
    }
  end

  @doc """
  Starts a `Abyss` instance with the given options. Returns a pid
  that can be used to further manipulate the server via other functions defined on
  this module in the case of success, or an error tuple describing the reason the
  server was unable to start in the case of failure.
  """
  @spec start_link(options()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    opts
    |> Abyss.ServerConfig.new()
    |> Abyss.Server.start_link()
  end

  @doc """
  Returns information about the address and port that the server is listening on
  """
  @spec listener_info(Supervisor.supervisor()) ::
          {:ok, Abyss.Transport.socket_info()} | :error
  def listener_info(supervisor) do
    case Abyss.Server.listener_pid(supervisor) do
      nil -> :error
      pid -> {:ok, Abyss.Listener.listener_info(pid)}
    end
  end

  @doc """
  Gets a list of active connection processes. This is inherently a bit of a leaky notion in the
  face of concurrency, as there may be connections coming and going during the period that this
  function takes to run. Callers should account for the possibility that new connections may have
  been made since / during this call, and that processes returned by this call may have since
  completed. The order that connection processes are returned in is not specified
  """
  @spec connection_pids(Supervisor.supervisor()) :: {:ok, [pid()]} | :error
  def connection_pids(supervisor) do
    case Abyss.Server.acceptor_pool_supervisor_pid(supervisor) do
      nil -> :error
      acceptor_pool_pid -> {:ok, collect_connection_pids(acceptor_pool_pid)}
    end
  end

  @doc """
  Suspend the server. This will close the listening port, and will stop the acceptance of new
  connections. Existing connections will stay connected and will continue to be processed.

  The server can later be resumed by calling `resume/1`, or shut down via standard supervision
  patterns.

  If this function returns `:error`, it is unlikely that the server is in a useable state

  Note that if you do not explicitly set a port (or if you set port to `0`), then the server will
  bind to a different port when you resume it. This new port can be obtained as usual via the
  `listener_info/1` function. This is not a concern if you explicitly set a port value when first
  instantiating the server
  """
  defdelegate suspend(supervisor), to: Abyss.Server

  @doc """
  Resume a suspended server. This will reopen the listening port, and resume the acceptance of new
  connections
  """
  defdelegate resume(supervisor), to: Abyss.Server

  defp collect_connection_pids(acceptor_pool_pid) do
    acceptor_pool_pid
    |> Abyss.AcceptorPoolSupervisor.acceptor_supervisor_pids()
    |> Enum.reduce([], fn acceptor_sup_pid, acc ->
      case Abyss.AcceptorSupervisor.connection_sup_pid(acceptor_sup_pid) do
        nil -> acc
        connection_sup_pid -> connection_pids(connection_sup_pid, acc)
      end
    end)
  end

  defp connection_pids(connection_sup_pid, acc) do
    connection_sup_pid
    |> DynamicSupervisor.which_children()
    |> Enum.reduce(acc, fn
      {_, connection_pid, _, _}, acc when is_pid(connection_pid) ->
        [connection_pid | acc]

      _, acc ->
        acc
    end)
  end

  @doc """
  Synchronously stops the given server, waiting up to the given number of milliseconds
  for existing connections to finish up. Immediately upon calling this function,
  the server stops listening for new connections, and then proceeds to wait until
  either all existing connections have completed or the specified timeout has
  elapsed.
  """
  @spec stop(Supervisor.supervisor(), timeout()) :: :ok
  def stop(supervisor, connection_wait \\ 15_000) do
    Supervisor.stop(supervisor, :normal, connection_wait)
  end
end
