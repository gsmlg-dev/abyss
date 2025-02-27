defmodule Echo do
  @behaviour Abyss.Handler

  use GenServer, restart: :temporary

  @spec start_link({handler_options :: term(), GenServer.options()}) :: GenServer.on_start()
  def start_link({handler_options, genserver_options}) do
    GenServer.start_link(__MODULE__, handler_options, genserver_options)
  end

  @impl true
  def init(handler_options) do
    Process.flag(:trap_exit, true)
    {:ok, {nil, nil, handler_options}}
  end

  @impl true
  def handle_info(
        {:abyss_ready, listener_socket, {ip, port, data}, server_config, acceptor_span,
         start_time},
        {nil, nil, state}
      ) do
    connection_span =
      Abyss.Telemetry.start_child_span(
        acceptor_span,
        :connection,
        %{monotonic_time: start_time},
        %{remote_address: ip, remote_port: port}
      )

    socket = listener_socket
    Abyss.Telemetry.span_event(connection_span, :ready)

    {:noreply, {socket, {ip, port}, state, server_config}, {:continue, {:handle_recv, data}}}
  catch
    {:stop, _, _} = stop -> stop
  end

  @impl true
  def handle_continue({:handle_recv, data}, {socket, {ip, port}, handler_options, server_config}) do
    case handle_data(data, ip, port, socket, handler_options) do
      {:close, handler_options} ->
        {:stop, :normal, handler_options}
        # _ -> {:noreply, {socket, {ip, port}, handler_options}}
    end
  end

  # Called if the remote end closed the connection before we could initialize it
  @impl true
  def terminate({:shutdown, {:premature_conn_closing, _reason}}, {_raw_socket, _state}) do
    :ok
  end

  # Called by GenServer if we hit our read_timeout. Socket is still open
  def terminate({:shutdown, :timeout}, {%Abyss.Socket{} = socket, state}) do
    _ = __MODULE__.handle_timeout(socket, state)
  end

  # Called if we're being shutdown in an orderly manner. Socket is still open
  def terminate(:shutdown, {%Abyss.Socket{} = socket, state}) do
    _ = __MODULE__.handle_shutdown(socket, state)
  end

  # Called if the socket encountered an error and we are configured to shutdown silently.
  # Socket is closed
  def terminate(
        {:shutdown, {:silent_termination, reason}},
        {%Abyss.Socket{} = socket, state}
      ) do
    _ = __MODULE__.handle_error(reason, socket, state)
  end

  # Called if the socket encountered an error during upgrading
  def terminate({:shutdown, {:upgrade, reason}}, {socket, state}) do
    _ = __MODULE__.handle_error(reason, socket, state)
  end

  # Called if the remote end shut down the connection, or if the local end closed the
  # connection by returning a `{:close,...}` tuple (in which case the socket will be open)
  def terminate({:shutdown, _reason}, {%Abyss.Socket{} = socket, state}) do
    _ = __MODULE__.handle_close(socket, state)
  end

  # Called if the socket encountered an error. Socket is closed
  def terminate(reason, {%Abyss.Socket{} = socket, state}) do
    _ = __MODULE__.handle_error(reason, socket, state)
  end

  # This clause could happen if we do not have a socket defined in state (either because the
  # process crashed before setting it up, or because the user sent an invalid state)
  def terminate(_reason, _state) do
    :ok
  end

  @impl true
  def handle_connection(_socket, state), do: {:continue, state}

  @impl true
  def handle_close(_socket, _state), do: :ok

  @impl true
  def handle_error(_error, _socket, _state), do: :ok

  @impl true
  def handle_shutdown(_socket, _state), do: :ok

  @impl true
  def handle_timeout(_socket, _state), do: :ok

  @impl true
  def handle_data(_data, _socket, state), do: {:continue, state}

  def handle_data(data, ip, port, listener_socket, handler_options) do
    IO.inspect(
      {"Received data:", data, "from peer:", ip, port, "with handler_options:", handler_options}
    )

    msg = "Echo #{inspect(listener_socket)}: #{data}"
    IO.inspect("Sending: #{msg}")
    :gen_udp.send(listener_socket, ip, port, msg) |> IO.inspect()
    {:close, handler_options}
  end
end
