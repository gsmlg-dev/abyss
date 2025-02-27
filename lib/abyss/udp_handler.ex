defmodule Abyss.UDPHandler do
  @moduledoc """
  `Abyss.UDPHandler` defines the behaviour required of the application layer of a Abyss server. When starting a
  Abyss server, you must pass the name of a module implementing this behaviour as the `handler_module` parameter.
  Abyss will then use the specified module to handle each connection that is made to the server.

  The lifecycle of a Handler instance is as follows:

  1. After a client connection to a Abyss server is made, Abyss will complete the initial setup of the
  connection (performing a TLS handshake, for example), and then call `c:handle_connection/2`.

  2. A handler implementation may choose to process a client connection within the `c:handle_connection/2` callback by
  calling functions against the passed `Abyss.Socket`. In many cases, this may be all that may be required of
  an implementation & the value `{:close, state}` can be returned which will cause Abyss to close the connection
  to the client.

  3. In cases where the server wishes to keep the connection open and wait for subsequent requests from the client on the
  same socket, it may elect to return `{:continue, state}`. This will cause Abyss to wait for client data
  asynchronously; `c:handle_data/4` will be invoked when the client sends more data.

  4. In the meantime, the process which is hosting connection is idle & able to receive messages sent from elsewhere in your
  application as needed. The implementation included in the `use Abyss.UDPHandler` macro uses a `GenServer` structure,
  so you may implement such behaviour via standard `GenServer` patterns. Note that in these cases that state is provided (and
  must be returned) in a `{socket, state}` format, where the second tuple is the same state value that is passed to the various `handle_*` callbacks
  defined on this behaviour. It also critical to maintain the socket's `read_timeout` value by
  ensuring the relevant timeout value is returned as your callback's final argument. Both of these
  concerns are illustrated in the following example:

      ```elixir
      defmodule ExampleHandler do
        use Abyss.UDPHandler

        # ...handle_data and other Handler callbacks

        @impl GenServer
        def handle_call(msg, from, {socket, state}) do
          # Do whatever you'd like with msg & from
          {:reply, :ok, {socket, state}, socket.read_timeout}
        end

        @impl GenServer
        def handle_cast(msg, {socket, state}) do
          # Do whatever you'd like with msg
          {:noreply, {socket, state}, socket.read_timeout}
        end

        @impl GenServer
        def handle_info(msg, {socket, state}) do
          # Do whatever you'd like with msg
          {:noreply, {socket, state}, socket.read_timeout}
        end
      end
      ```

  It is fully supported to intermix synchronous `Abyss.Socket.recv` calls with async return values from `c:handle_connection/2`
  and `c:handle_data/4` callbacks.

  # Example

  A simple example of a Hello World server is as follows:

  ```elixir
  defmodule HelloWorld do
    use Abyss.UDPHandler

    @impl Abyss.UDPHandler
    def handle_connection(socket, state) do
      Abyss.Socket.send(socket, "Hello, World")
      {:close, state}
    end
  end
  ```

  Another example of a server that echoes back all data sent to it is as follows:

  ```elixir
  defmodule Echo do
    use Abyss.UDPHandler

    @impl Abyss.UDPHandler
    def handle_data(data, socket, state) do
      Abyss.Socket.send(socket, data)
      {:continue, state}
    end
  end
  ```

  Note that in this example there is no `c:handle_connection/2` callback defined. The default implementation of this
  callback will simply return `{:continue, state}`, which is appropriate for cases where the client is the first
  party to communicate.

  Another example of a server which can send and receive messages asynchronously is as follows:

  ```elixir
  defmodule Messenger do
    use Abyss.UDPHandler

    @impl Abyss.UDPHandler
    def handle_data(msg, _socket, state) do
      IO.puts(msg)
      {:continue, state}
    end

    def handle_info({:send, msg}, {socket, state}) do
      Abyss.Socket.send(socket, msg)
      {:noreply, {socket, state}, socket.read_timeout}
    end
  end
  ```

  Note that in this example we make use of the fact that the handler process is really just a GenServer to send it messages
  which are able to make use of the underlying socket. This allows for bidirectional sending and receiving of messages in
  an asynchronous manner.

  You can pass options to the default handler underlying `GenServer` by passing a `genserver_options` key to `Abyss.start_link/1`
  containing `t:GenServer.options/0` to be passed to the last argument of `GenServer.start_link/3`.

  Please note that you should not pass the `name` `t:GenServer.option/0`. If you need to register handler processes for
  later lookup and use, you should perform process registration in `handle_connection/2`, ensuring the handler process is
  registered only after the underlying connection is established and you have access to the connection socket and metadata
  via `Abyss.Socket.peername/1`.

  For example, using a custom process registry via `Registry`:

  ```elixir

  defmodule Messenger do
    use Abyss.UDPHandler

    @impl Abyss.UDPHandler
    def handle_connection(socket, state) do
      {:ok, {ip, port}} = Abyss.Socket.peername(socket)
      {:ok, _pid} = Registry.register(MessengerRegistry, {state[:my_key], address}, nil)
      {:continue, state}
    end

    @impl Abyss.UDPHandler
    def handle_data(data, socket, state) do
      Abyss.Socket.send(socket, data)
      {:continue, state}
    end
  end
  ```

  This example assumes you have started a `Registry` and registered it under the name `MessengerRegistry`.

  # When Handler Isn't Enough

  The `use Abyss.UDPHandler` implementation should be flexible enough to power just about any handler, however if
  this should not be the case for you, there is an escape hatch available. If you require more flexibility than the
  `Abyss.UDPHandler` behaviour provides, you are free to specify any module which implements `start_link/1` as the
  `handler_module` parameter. The process of getting from this new process to a ready-to-use socket is somewhat
  delicate, however. The steps required are as follows:

  1. Abyss calls `start_link/1` on the configured `handler_module`, passing in a tuple
  consisting of the configured handler and genserver opts. This function is expected to return a
  conventional `GenServer.on_start()` style tuple. Note that this newly created process is not
  passed the connection socket immediately.
  2. The raw `t:Abyss.Transport.socket()` socket will be passed to the new process via a
  message of the form `{:abyss_ready, raw_socket, server_config, acceptor_span,
  start_time}`.
  3. Your implenentation must turn this into a `to:Abyss.Socket.t()` socket by using the
  `Abyss.Socket.new/3` call.
  4. Your implementation must then call `Abyss.Socket.handshake/1` with the socket as the
  sole argument in order to finalize the setup of the socket.
  5. The socket is now ready to use.

  In addition to this process, there are several other considerations to be aware of:

  * The underlying socket is closed automatically when the handler process ends.

  * Handler processes should have a restart strategy of `:temporary` to ensure that Abyss does not attempt to
  restart crashed handlers.

  * Handler processes should trap exit if possible so that existing connections can be given a chance to cleanly shut
  down when shutting down a Abyss server instance.

  * Some of the `:connection` family of telemetry span events are emitted by the
  `Abyss.UDPHandler` implementation. If you use your own implementation in its place it is
  likely that such spans will not behave as expected.
  """

  @typedoc "The possible ways to indicate a timeout when returning values to Abyss"
  @type timeout_options :: timeout() | {:persistent, timeout()}

  @typedoc "The value returned by `c:handle_connection/2` and `c:handle_data/4`"
  @type handler_result ::
          {:continue, state :: term()}
          | {:continue, state :: term(), timeout_options()}
          | {:switch_transport, {module(), upgrade_opts :: [term()]}, state :: term()}
          | {:switch_transport, {module(), upgrade_opts :: [term()]}, state :: term(),
             timeout_options()}
          | {:close, state :: term()}
          | {:error, term(), state :: term()}

  @doc """
  This callback is called shortly after a client connection has been made, immediately after the socket handshake process has
  completed. It is called with the server's configured `handler_options` value as initial state. Handlers may choose to
  interact synchronously with the socket in this callback via calls to various `Abyss.Socket` functions.

  The value returned by this callback causes Abyss to proceed in one of several ways:

  * Returning `{:close, state}` will cause Abyss to close the socket & call the `c:handle_close/2` callback to
  allow final cleanup to be done.
  * Returning `{:continue, state}` will cause Abyss to switch the socket to an asynchronous mode. When the
  client subsequently sends data (or if there is already unread data waiting from the client), Abyss will call
  `c:handle_data/4` to allow this data to be processed.
  * Returning `{:continue, state, timeout}` is identical to the previous case with the
  addition of a timeout. If `timeout` milliseconds passes with no data being received or messages
  being sent to the process, the socket will be closed and `c:handle_timeout/2` will be called.
  Note that this timeout is not persistent; it applies only to the interval until the next message
  is received. In order to set a persistent timeout for all future messages (essentially
  overwriting the value of `read_timeout` that was set at server startup), a value of
  `{:persistent, timeout}` may be returned.
  * Returning `{:switch_transport, {module, opts}, state}` will cause Abyss to try switching the transport of the
  current socket. The `module` should be an Elixir module that implements the `Abyss.Transport` behaviour.
  Abyss will call `c:Abyss.Transport.upgrade/2` for the given module to upgrade the transport in-place.
  After a successful upgrade Abyss will switch the socket to an asynchronous mode, as if `{:continue, state}`
  was returned. As with `:continue` return values, there are also timeout-specifying variants of
  this return value.
  * Returning `{:error, reason, state}` will cause Abyss to close the socket & call the `c:handle_error/3` callback to
  allow final cleanup to be done.
  """
  @callback handle_connection(socket :: Abyss.Socket.t(), state :: term()) ::
              handler_result()

  @doc """
  This callback is called whenever client data is received after `c:handle_connection/2` or `c:handle_data/4` have returned an
  `{:continue, state}` tuple. The data received is passed as the first argument, and handlers may choose to interact
  synchronously with the socket in this callback via calls to various `Abyss.Socket` functions.

  The value returned by this callback causes Abyss to proceed in one of several ways:

  * Returning `{:close, state}` will cause Abyss to close the socket & call the `c:handle_close/2` callback to
  allow final cleanup to be done.
  * Returning `{:continue, state}` will cause Abyss to switch the socket to an asynchronous mode. When the
  client subsequently sends data (or if there is already unread data waiting from the client), Abyss will call
  `c:handle_data/4` to allow this data to be processed.
  * Returning `{:continue, state, timeout}` is identical to the previous case with the
  addition of a timeout. If `timeout` milliseconds passes with no data being received or messages
  being sent to the process, the socket will be closed and `c:handle_timeout/2` will be called.
  Note that this timeout is not persistent; it applies only to the interval until the next message
  is received. In order to set a persistent timeout for all future messages (essentially
  overwriting the value of `read_timeout` that was set at server startup), a value of
  `{:persistent, timeout}` may be returned.
  * Returning `{:error, reason, state}` will cause Abyss to close the socket & call the `c:handle_error/3` callback to
  allow final cleanup to be done.
  """
  @callback handle_data(data :: binary(), peer :: {:inet.ip_address(), :inet.port_number()}, socket :: Abyss.Socket.t(), state :: term()) ::
              handler_result()

  @doc """
  This callback is called when the underlying socket is closed by the remote end; it should perform any cleanup required
  as it is the last callback called before the process backing this connection is terminated. The underlying socket
  has already been closed by the time this callback is called. The return value is ignored.

  This callback is not called if the connection is explicitly closed via `Abyss.Socket.close/1`, however it
  will be called in cases where `handle_connection/2` or `handle_data/4` return a `{:close, state}` tuple.
  """
  @callback handle_close(socket :: Abyss.Socket.t(), state :: term()) :: term()

  @doc """
  This callback is called when the underlying socket encounters an error; it should perform any cleanup required
  as it is the last callback called before the process backing this connection is terminated. The underlying socket
  has already been closed by the time this callback is called. The return value is ignored.

  In addition to socket level errors, this callback is also called in cases where `handle_connection/2` or `handle_data/4`
  return a `{:error, reason, state}` tuple, or when connection handshaking (typically TLS
  negotiation) fails.
  """
  @callback handle_error(reason :: any(), socket :: Abyss.Socket.t(), state :: term()) ::
              term()

  @doc """
  This callback is called when the server process itself is being shut down; it should perform any cleanup required
  as it is the last callback called before the process backing this connection is terminated. The underlying socket
  has NOT been closed by the time this callback is called. The return value is ignored.

  This callback is only called when the shutdown reason is `:normal`, and is subject to the same caveats described
  in `c:GenServer.terminate/2`.
  """
  @callback handle_shutdown(socket :: Abyss.Socket.t(), state :: term()) :: term()

  @doc """
  This callback is called when a handler process has gone more than `timeout` ms without receiving
  either remote data or a local message. The value used for `timeout` defaults to the
  `read_timeout` value specified at server startup, and may be overridden on a one-shot or
  persistent basis based on values returned from `c:handle_connection/2` or `c:handle_data/4`
  calls. Note that it is NOT called on explicit `Abyss.Socket.recv/3` calls as they have
  their own timeout semantics. The underlying socket has NOT been closed by the time this callback
  is called. The return value is ignored.
  """
  @callback handle_timeout(socket :: Abyss.Socket.t(), state :: term()) :: term()

  @optional_callbacks handle_connection: 2,
                      handle_data: 4,
                      handle_close: 2,
                      handle_error: 3,
                      handle_shutdown: 2,
                      handle_timeout: 2

  @spec __using__(any) :: Macro.t()
  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Abyss.UDPHandler

      use GenServer, restart: :temporary

      @spec start_link({handler_options :: term(), GenServer.options()}) :: GenServer.on_start()
      def start_link({handler_options, genserver_options}) do
        GenServer.start_link(__MODULE__, handler_options, genserver_options)
      end

      unquote(genserver_impl())
      unquote(handler_impl())
    end
  end

  @doc false
  defmacro add_handle_info_fallback(_module) do
    quote do
      def handle_info({msg, _raw_socket, _data}, _state) when msg in [:tcp, :ssl] do
        raise """
          The callback's `state` doesn't match the expected `{socket, state}` form.
          Please ensure that you are returning a `{socket, state}` tuple from any
          `GenServer.handle_*` callbacks you have implemented
        """
      end
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def genserver_impl do
    quote do
      @impl true
      def init(handler_options) do
        Process.flag(:trap_exit, true)
        {:ok, {nil, handler_options}}
      end

      @impl true
      def handle_info(
            {:abyss_ready, {listener_socket, {ip, port, data}}, server_config, acceptor_span, start_time},
            {nil, state}
          ) do

        span_meta = %{remote_address: ip, remote_port: port}

        connection_span =
          Abyss.Telemetry.start_child_span(
            acceptor_span,
            :connection,
            %{monotonic_time: start_time},
            span_meta
          )

        socket = Abyss.Socket.new(listener_socket, server_config, connection_span)
        Abyss.Telemetry.span_event(connection_span, :ready)

        case Abyss.Socket.handshake(socket) do
          {:ok, socket} -> {:noreply, {socket, state}, {:continue, :handle_connection}}
          {:error, reason} -> {:stop, {:shutdown, {:handshake, reason}}, {socket, state}}
        end
      catch
        {:stop, _, _} = stop -> stop
      end

      def handle_info(
            {msg, raw_socket, data},
            {%Abyss.Socket{socket: raw_socket} = socket, state}
          )
          when msg in [:tcp, :ssl] do
        Abyss.Telemetry.untimed_span_event(socket.span, :async_recv, %{data: data})

        __MODULE__.handle_data(data, socket, state)
        |> Abyss.UDPHandler.handle_continuation(socket)
      end

      def handle_info(
            {msg, raw_socket},
            {%Abyss.Socket{socket: raw_socket} = socket, state}
          )
          when msg in [:tcp_closed, :ssl_closed] do
        {:stop, {:shutdown, :peer_closed}, {socket, state}}
      end

      def handle_info(
            {msg, raw_socket, reason},
            {%Abyss.Socket{socket: raw_socket} = socket, state}
          )
          when msg in [:tcp_error, :ssl_error] do
        {:stop, reason, {socket, state}}
      end

      def handle_info(:timeout, {%Abyss.Socket{} = socket, state}) do
        {:stop, {:shutdown, :timeout}, {socket, state}}
      end

      @before_compile {Abyss.UDPHandler, :add_handle_info_fallback}

      # Use a continue pattern here so that we have committed the socket
      # to state in case the `c:handle_connection/2` callback raises an error.
      # This ensures that the `c:terminate/2` calls below are able to properly
      # close down the process
      @impl true
      def handle_continue(:handle_connection, {%Abyss.Socket{} = socket, state}) do
        __MODULE__.handle_connection(socket, state)
        |> Abyss.UDPHandler.handle_continuation(socket)
      end

      # Called if the remote end closed the connection before we could initialize it
      @impl true
      def terminate({:shutdown, {:premature_conn_closing, _reason}}, {_raw_socket, _state}) do
        :ok
      end

      # Called by GenServer if we hit our read_timeout. Socket is still open
      def terminate({:shutdown, :timeout}, {%Abyss.Socket{} = socket, state}) do
        _ = __MODULE__.handle_timeout(socket, state)
        Abyss.UDPHandler.do_socket_close(socket, :timeout)
      end

      # Called if we're being shutdown in an orderly manner. Socket is still open
      def terminate(:shutdown, {%Abyss.Socket{} = socket, state}) do
        _ = __MODULE__.handle_shutdown(socket, state)
        Abyss.UDPHandler.do_socket_close(socket, :shutdown)
      end

      # Called if the socket encountered an error during handshaking
      def terminate({:shutdown, {:handshake, reason}}, {%Abyss.Socket{} = socket, state}) do
        _ = __MODULE__.handle_error(reason, socket, state)
        Abyss.UDPHandler.do_socket_close(socket, reason)
      end

      # Called if the socket encountered an error and we are configured to shutdown silently.
      # Socket is closed
      def terminate(
            {:shutdown, {:silent_termination, reason}},
            {%Abyss.Socket{} = socket, state}
          ) do
        _ = __MODULE__.handle_error(reason, socket, state)
        Abyss.UDPHandler.do_socket_close(socket, reason)
      end

      # Called if the socket encountered an error during upgrading
      def terminate({:shutdown, {:upgrade, reason}}, {socket, state}) do
        _ = __MODULE__.handle_error(reason, socket, state)
        Abyss.UDPHandler.do_socket_close(socket, reason)
      end

      # Called if the remote end shut down the connection, or if the local end closed the
      # connection by returning a `{:close,...}` tuple (in which case the socket will be open)
      def terminate({:shutdown, reason}, {%Abyss.Socket{} = socket, state}) do
        _ = __MODULE__.handle_close(socket, state)
        Abyss.UDPHandler.do_socket_close(socket, reason)
      end

      # Called if the socket encountered an error. Socket is closed
      def terminate(reason, {%Abyss.Socket{} = socket, state}) do
        _ = __MODULE__.handle_error(reason, socket, state)
        Abyss.UDPHandler.do_socket_close(socket, reason)
      end

      # This clause could happen if we do not have a socket defined in state (either because the
      # process crashed before setting it up, or because the user sent an invalid state)
      def terminate(_reason, _state) do
        :ok
      end
    end
  end

  def handler_impl do
    quote do
      @impl true
      def handle_connection(_socket, state), do: {:continue, state}

      @impl true
      def handle_data(_data, _peer, _socket, state), do: {:continue, state}

      @impl true
      def handle_close(_socket, _state), do: :ok

      @impl true
      def handle_error(_error, _socket, _state), do: :ok

      @impl true
      def handle_shutdown(_socket, _state), do: :ok

      @impl true
      def handle_timeout(_socket, _state), do: :ok

      defoverridable Abyss.UDPHandler
    end
  end

  @spec do_socket_close(
          Abyss.Socket.t(),
          reason :: :shutdown | :local_closed | term()
        ) :: :ok
  @doc false
  def do_socket_close(socket, reason) do
    measurements =
      case Abyss.Socket.getstat(socket) do
        {:ok, stats} ->
          stats
          |> Keyword.take([:send_oct, :send_cnt, :recv_oct, :recv_cnt])
          |> Enum.into(%{})

        _ ->
          %{}
      end

    metadata =
      if reason in [:shutdown, :local_closed, :peer_closed], do: %{}, else: %{error: reason}

    _ = Abyss.Socket.close(socket)
    Abyss.Telemetry.stop_span(socket.span, measurements, metadata)
  end

  @doc false
  def handle_continuation(continuation, socket) do
    case continuation do
      {:close, state} ->
        {:stop, {:shutdown, :local_closed}, {socket, state}}

      {:error, :timeout, state} ->
        {:stop, {:shutdown, :timeout}, {socket, state}}

      {:error, reason, state} ->
        if socket.silent_terminate_on_error do
          {:stop, {:shutdown, {:silent_termination, reason}}, {socket, state}}
        else
          {:stop, reason, {socket, state}}
        end
    end
  end

end
