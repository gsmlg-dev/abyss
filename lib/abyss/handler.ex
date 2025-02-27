defmodule Abyss.Handler do
  @moduledoc """
  `Abyss.Handler` defines the behaviour required of the application layer of a Abyss server. When starting a
  Abyss server, you must pass the name of a module implementing this behaviour as the `handler_module` parameter.
  Abyss will then use the specified module to handle each connection that is made to the server.

      ```elixir
      defmodule ExampleHandler do
        use Abyss.Handler

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
  and `c:handle_data/3` callbacks.

  # Example

  A simple example of a Hello World server is as follows:

  ```elixir
  defmodule HelloWorld do
    use Abyss.Handler

    @impl Abyss.Handler
    def handle_connection(socket, state) do
      Abyss.Socket.send(socket, "Hello, World")
      {:close, state}
    end
  end
  ```

  Another example of a server that echoes back all data sent to it is as follows:

  ```elixir
  defmodule Echo do
    use Abyss.Handler

    @impl Abyss.Handler
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
    use Abyss.Handler

    @impl Abyss.Handler
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
    use Abyss.Handler

    @impl Abyss.Handler
    def handle_connection(socket, state) do
      {:ok, {ip, port}} = Abyss.Socket.peername(socket)
      {:ok, _pid} = Registry.register(MessengerRegistry, {state[:my_key], address}, nil)
      {:continue, state}
    end

    @impl Abyss.Handler
    def handle_data(data, socket, state) do
      Abyss.Socket.send(socket, data)
      {:continue, state}
    end
  end
  ```

  This example assumes you have started a `Registry` and registered it under the name `MessengerRegistry`.

  # When Handler Isn't Enough

  The `use Abyss.Handler` implementation should be flexible enough to power just about any handler, however if
  this should not be the case for you, there is an escape hatch available. If you require more flexibility than the
  `Abyss.Handler` behaviour provides, you are free to specify any module which implements `start_link/1` as the
  `handler_module` parameter. The process of getting from this new process to a ready-to-use socket is somewhat
  delicate, however. The steps required are as follows:

  1. Abyss calls `start_link/1` on the configured `handler_module`, passing in a tuple
  consisting of the configured handler and genserver opts. This function is expected to return a
  conventional `GenServer.on_start()` style tuple. Note that this newly created process is not
  passed the connection socket immediately.
  2. The raw `t:Abyss.Transport.socket()` socket will be passed to the new process via a
  message of the form `{:abyss_received, listener_socket, server_config, acceptor_span,
  start_time}`.
  3. Your implenentation must turn this into a `to::inet.socket()` socket by using the
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
  `Abyss.Handler` implementation. If you use your own implementation in its place it is
  likely that such spans will not behave as expected.
  """

  alias Abyss.HandlerState

  @typedoc "The possible ways to indicate a timeout when returning values to Abyss"
  @type timeout_options :: timeout() | {:persistent, timeout()}

  @typedoc "The value returned by `c:handle_connection/2` and `c:handle_data/3`"
  @type handler_result ::
          {:continue, state :: term()}
          | {:continue, state :: term(), timeout_options()}
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
  `c:handle_data/3` to allow this data to be processed.
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
  @callback handle_connection(
              remote :: {:inet.ip_address(), :inet.port_number()},
              state :: term()
            ) ::
              handler_result()

  @doc """
  This callback is called whenever client data is received after `c:handle_connection/2` or `c:handle_data/3` have returned an
  `{:continue, state}` tuple. The data received is passed as the first argument, and handlers may choose to interact
  synchronously with the socket in this callback via calls to various `Abyss.Socket` functions.

  The value returned by this callback causes Abyss to proceed in one of several ways:

  * Returning `{:close, state}` will cause Abyss to close the socket & call the `c:handle_close/2` callback to
  allow final cleanup to be done.
  * Returning `{:continue, state}` will cause Abyss to switch the socket to an asynchronous mode. When the
  client subsequently sends data (or if there is already unread data waiting from the client), Abyss will call
  `c:handle_data/3` to allow this data to be processed.
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
  @callback handle_data(data :: binary(), state :: term()) ::
              handler_result()

  @doc """
  This callback is called when the underlying socket is closed by the remote end; it should perform any cleanup required
  as it is the last callback called before the process backing this connection is terminated. The underlying socket
  has already been closed by the time this callback is called. The return value is ignored.

  This callback is not called if the connection is explicitly closed via `Abyss.Socket.close/1`, however it
  will be called in cases where `handle_connection/2` or `handle_data/3` return a `{:close, state}` tuple.
  """
  @callback handle_close(state :: term()) :: term()

  @doc """
  This callback is called when the underlying socket encounters an error; it should perform any cleanup required
  as it is the last callback called before the process backing this connection is terminated. The underlying socket
  has already been closed by the time this callback is called. The return value is ignored.

  In addition to socket level errors, this callback is also called in cases where `handle_connection/2` or `handle_data/3`
  return a `{:error, reason, state}` tuple, or when connection handshaking (typically TLS
  negotiation) fails.
  """
  @callback handle_error(reason :: any(), state :: term()) ::
              term()

  @doc """
  This callback is called when the server process itself is being shut down; it should perform any cleanup required
  as it is the last callback called before the process backing this connection is terminated. The underlying socket
  has NOT been closed by the time this callback is called. The return value is ignored.

  This callback is only called when the shutdown reason is `:normal`, and is subject to the same caveats described
  in `c:GenServer.terminate/2`.
  """
  @callback handle_shutdown(state :: term()) :: term()

  @doc """
  This callback is called when a handler process has gone more than `timeout` ms without receiving
  either remote data or a local message. The value used for `timeout` defaults to the
  `read_timeout` value specified at server startup, and may be overridden on a one-shot or
  persistent basis based on values returned from `c:handle_connection/2` or `c:handle_data/3`
  calls. Note that it is NOT called on explicit `Abyss.Socket.recv/3` calls as they have
  their own timeout semantics. The underlying socket has NOT been closed by the time this callback
  is called. The return value is ignored.
  """
  @callback handle_timeout(state :: term()) :: term()

  @optional_callbacks handle_connection: 2,
                      handle_data: 2,
                      handle_error: 2,
                      handle_close: 1,
                      handle_shutdown: 1,
                      handle_timeout: 1

  @spec __using__(any) :: Macro.t()
  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Abyss.Handler

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
      def handle_info({msg, _raw_ip, _port, _data}, _state) when msg in [:udp] do
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
        {:ok, %HandlerState{handler_options: handler_options}}
      end

      @impl true
      def handle_info(
            {:abyss_received, listener_socket, recv_data, server_config, acceptor_span,
             start_time},
            state
          ) do
        {ip, port, data} = recv_data

        connection_span =
          Abyss.Telemetry.start_child_span(
            acceptor_span,
            :connection,
            %{monotonic_time: start_time},
            %{remote_address: ip, remote_port: port}
          )

        Abyss.Telemetry.span_event(connection_span, :ready)

        {:noreply,
         %HandlerState{
           state
           | listener: listener_socket,
             remote: {ip, port},
             server_config: server_config,
             connection_span: connection_span
         }, {:continue, {:handle_connection, {ip, port}, data}}}
      catch
        {:stop, _, _} = stop -> stop
      end

      def handle_info(:timeout, state) do
        {:stop, {:shutdown, :timeout}, state}
      end

      @before_compile {Abyss.Handler, :add_handle_info_fallback}

      # Use a continue pattern here so that we have committed the socket
      # to state in case the `c:handle_connection/2` callback raises an error.
      # This ensures that the `c:terminate/2` calls below are able to properly
      # close down the process
      @impl true
      def handle_continue({:handle_connection, remote, data}, state) do
        __MODULE__.handle_connection(remote, state)
        |> Abyss.Handler.handle_continuation(state, data)
      end

      def handle_continue({:handle_data, data}, state) do
        __MODULE__.handle_data(data, state)
        |> Abyss.Handler.handle_continuation(state)
      end

      @impl true
      # Called by GenServer if we hit our read_timeout. Socket is still open
      def terminate({:shutdown, :timeout}, state) do
        _ = __MODULE__.handle_timeout(state)
      end

      # Called if we're being shutdown in an orderly manner. Socket is still open
      def terminate(:shutdown, state) do
        _ = __MODULE__.handle_shutdown(state)
      end

      # Called if the socket encountered an error and we are configured to shutdown silently.
      # Socket is closed
      def terminate(
            {:shutdown, {:silent_termination, reason}},
            state
          ) do
        _ = __MODULE__.handle_error(reason, state)
      end

      # Called if the remote end shut down the connection, or if the local end closed the
      # connection by returning a `{:close,...}` tuple (in which case the socket will be open)
      def terminate({:shutdown, reason}, state) do
        _ = __MODULE__.handle_close(state)
      end

      # Called if the socket encountered an error. Socket is closed
      def terminate(reason, state) do
        _ = __MODULE__.handle_error(reason, state)
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
      def handle_connection(_remote, state), do: {:continue, state}

      @impl true
      def handle_data(_data, state), do: {:close, state}

      @impl true
      def handle_close(_state), do: :ok

      @impl true
      def handle_error(_error, _state), do: :ok

      @impl true
      def handle_shutdown(_state), do: :ok

      @impl true
      def handle_timeout(_state), do: :ok

      defoverridable Abyss.Handler
    end
  end

  @doc false
  def handle_continuation(continuation, state, data \\ nil) do
    case continuation do
      {:continue, _state} ->
        if is_nil(data) do
          {:noreply, state, state[:read_timeout]}
        else
          {:noreply, state, {:continue, {:handle_data, data}}}
        end

      {:close, _state} ->
        {:stop, {:shutdown, :local_closed}, state}

      {:error, :timeout, _state} ->
        {:stop, {:shutdown, :timeout}, state}

      {:error, reason, _state} ->
        if state.server_config.silent_terminate_on_error do
          {:stop, {:shutdown, {:silent_termination, reason}}, state}
        else
          {:stop, reason, state}
        end
    end
  end
end
