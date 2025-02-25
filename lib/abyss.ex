defmodule Abyss do
  @moduledoc """
  Abyss is a modern, pure Elixir socket server, inspired heavily by
  [ranch](https://github.com/ninenines/ranch). It aims to be easy to understand
  & reason about, while also being at least as stable and performant as alternatives.

  Abyss is implemented as a supervision tree which is intended to be hosted
  inside a host application, often as a dependency embedded within a higher-level
  protocol library such as [Bandit](https://github.com/mtrudel/bandit). Aside from
  supervising the Abyss process tree, applications interact with Abyss
  primarily via the `Abyss.Handler` behaviour.

  ## Handlers

  The `Abyss.Handler` behaviour defines the interface that Abyss
  uses to pass `Abyss.Socket`s up to the application level; together they
  form the primary interface that most applications will have with Abyss.
  Abyss comes with a few simple protocol handlers to serve as examples;
  these can be found in the [examples](https://github.com/mtrudel/abyss/tree/main/examples)
  folder of this project. A simple implementation would look like this:

  ```elixir
  defmodule Echo do
    use Abyss.Handler

    @impl Abyss.Handler
    def handle_data(data, socket, state) do
      Abyss.Socket.send(socket, data)
      {:continue, state}
    end
  end

  {:ok, pid} = Abyss.start_link(port: 1234, handler_module: Echo)
  ```

  For more information, please consult the `Abyss.Handler` documentation.

  ## Starting a Abyss Server

  A typical use of `Abyss` might look like the following:

  ```elixir
  defmodule MyApp.Supervisor do
    # ... other Supervisor boilerplate

    def init(config) do
      children = [
        # ... other children as dictated by your app
        {Abyss, port: 1234, handler_module: MyApp.ConnectionHandler}
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end
  ```

  You can also start servers directly via the `start_link/1` function:

  ```elixir
  {:ok, pid} = Abyss.start_link(port: 1234, handler_module: MyApp.ConnectionHandler)
  ```

  ## Configuration

  A number of options are defined when starting a server. The complete list is
  defined by the `t:Abyss.options/0` type.

  ## Connection Draining & Shutdown

  `Abyss` instances are just a process tree consisting of standard
  `Supervisor`, `GenServer` and `Task` modules, and so the usual rules regarding
  shutdown and shutdown timeouts apply. Immediately upon beginning the shutdown
  sequence the Abyss.ShutdownListener process will cause the listening
  socket to shut down. At this point all that
  is left in the supervision tree are several layers of Supervisors and whatever
  `Handler` processes were in progress when shutdown was initiated. At this
  point, standard `Supervisor` shutdown timeout semantics give existing
  connections a chance to finish things up. `Handler` processes trap exit, so
  they continue running beyond shutdown until they either complete or are
  `:brutal_kill`ed after their shutdown timeout expires.

  ## Logging & Telemetry

  As a low-level library, Abyss purposely does not do any inline
  logging of any kind. The `Abyss.Logger` module defines a number of
  functions to aid in tracing connections at various log levels, and such logging
  can be dynamically enabled and disabled against an already running server. This
  logging is backed by telemetry events internally.

  Abyss emits a rich set of telemetry events including spans for each
  server, acceptor process, and individual client connection. These telemetry
  events are documented in the `Abyss.Telemetry` module.
  """

  @typedoc """
  Possible options to configure a server. Valid option values are as follows:

  * `handler_module`: The name of the module used to handle connections to this server.
  The module is expected to implement the `Abyss.Handler` behaviour. Required
  * `handler_options`: A term which is passed as the initial state value to
  `c:Abyss.Handler.handle_connection/2` calls. Optional, defaulting to nil
  * `port`: The TCP port number to listen on. If not specified this defaults to 4000.
  If a port number of `0` is given, the server will dynamically assign a port number
  which can then be obtained via `Abyss.listener_info/1` or
  `Abyss.Socket.sockname/1`
  * `transport_module`: The name of the module which provides basic socket functions.
  Abyss provides `Abyss.Transports.TCP` and `Abyss.Transports.UDP`,
  which provide clear and TLS encrypted TCP sockets respectively. If not specified this
  defaults to `Abyss.Transports.TCP`
  * `transport_options`: A keyword list of options to be passed to the transport module's
  `c:Abyss.Transport.listen/2` function. Valid values depend on the transport
  module specified in `transport_module` and can be found in the documentation for the
  `Abyss.Transports.TCP` and `Abyss.Transports.UDP` modules. Any options
  in terms of interfaces to listen to / certificates and keys to use for SSL connections
  will be passed in via this option
  * `genserver_options`: A term which is passed as the option value to the handler module's
  underlying `GenServer.start_link/3` call. Optional, defaulting to `[]`
  * `supervisor_options`: A term which is passed as the option value to this server's top-level
  supervisor's `Supervisor.start_link/3` call. Useful for setting the `name` for this server.
  Optional, defaulting to `[]`
  * `num_acceptors`: The number of acceptor processes to run. Defaults to 100
  * `num_connections`: The maximum number of concurrent connections which each acceptor will
  accept before throttling connections. Connections will be throttled by having the acceptor
  process wait `max_connections_retry_wait` milliseconds, up to `max_connections_retry_count`
  times for existing connections to terminate & make room for this new connection. If there is
  still no room for this new connection after this interval, the acceptor will close the client
  connection and emit a `[:abyss, :acceptor, :spawn_error]` telemetry event. This number
  is expressed per-acceptor, so the total number of maximum connections for a Abyss
  server is `num_acceptors * num_connections`. Defaults to `16_384`
  * `max_connections_retry_wait`: How long to wait during each iteration as described in
  `num_connectors` above, in milliseconds. Defaults to `1000`
  * `max_connections_retry_count`: How many iterations to wait as described in `num_connectors`
  above. Defaults to `5`
  * `read_timeout`: How long to wait for client data before closing the connection, in
  milliseconds. Defaults to 60_000
  * `shutdown_timeout`: How long to wait for existing client connections to complete before
  forcibly shutting those connections down at server shutdown time, in milliseconds. Defaults to
  15_000. May also be `:infinity` or `:brutal_kill` as described in the `Supervisor`
  documentation
  * `silent_terminate_on_error`: Whether to silently ignore errors returned by the handler or to
  surface them to the runtime via an abnormal termination result. This only applies to errors
  returned via `{:error, reason, state}` responses; exceptions raised within a handler are always
  logged regardless of this value. Note also that telemetry events will always be sent for errors
  regardless of this value. Defaults to false
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
  @type transport_module :: Abyss.Transports.UDP

  @typedoc "A keyword list of options to be passed to the transport module's `listen/2` function"
  @type transport_options() :: :gen_udp.open_option()

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

defmodule Echo do
  use Abyss.Handler

  @impl Abyss.Handler
  def handle_data(data, socket, state) do
    IO.inspect({:data, data, socket, state})
    Abyss.Socket.send(socket, data)
    {:continue, state}
  end
end
