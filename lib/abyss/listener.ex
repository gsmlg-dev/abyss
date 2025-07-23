defmodule Abyss.Listener do
  @moduledoc false

  use GenServer, restart: :transient

  @type state :: %{
          is_active: boolean(),
          is_listening: boolean(),
          server_pid: pid(),
          server_config: Abyss.ServerConfig.t(),
          listener_id: binary(),
          listener_socket: Abyss.Transport.socket(),
          listener_span: Abyss.Telemetry.t(),
          local_info: Abyss.Transport.socket_info()
        }

  @spec start_link({id :: binary(), server_pid :: pid(), Abyss.ServerConfig.t()}) ::
          GenServer.on_start()
  def start_link({id, server_pid, config}),
    do: GenServer.start_link(__MODULE__, {id, server_pid, config})

  @spec stop(GenServer.server()) :: :ok
  def stop(server), do: GenServer.stop(server)

  @spec listener_info(GenServer.server()) :: Abyss.Transport.socket_info()
  def listener_info(server), do: GenServer.call(server, :listener_info)

  @spec socket_info(GenServer.server()) ::
          {Abyss.Transport.listener_socket(), Abyss.Telemetry.t()}
  def socket_info(server), do: GenServer.call(server, :socket_info)

  @impl GenServer
  @spec init({listener_id :: neg_integer(), server_pid :: pid(), Abyss.ServerConfig.t()}) ::
          {:ok, state} | {:stop, term}
  def init({listener_id, server_pid, server_config}) do
    broadcast = server_config.broadcast

    transport_options =
      if broadcast do
        server_config.transport_options
        |> Keyword.put(:active, true)
        |> Keyword.put(:broadcast, true)
      else
        server_config.transport_options
        |> Keyword.put(:active, false)
        |> Keyword.put(:broadcast, false)
      end

    with {:ok, listener_socket} <-
           Abyss.Transport.UDP.listen(
             server_config.port,
             transport_options
           ),
         {:ok, {ip, port}} <-
           :inet.sockname(listener_socket) do
      active =
        case Abyss.Transport.UDP.getopts(listener_socket, [:active]) do
          {:ok, [active: true]} -> true
          _ -> false
        end

      span_metadata = %{
        listener_id: listener_id,
        listener_socket: listener_socket,
        handler: server_config.handler_module,
        local_address: ip,
        local_port: port,
        broadcast: broadcast,
        transport_options: transport_options
      }

      listener_span = Abyss.Telemetry.start_span(:listener, %{}, span_metadata)

      state = %{
        broadcast: broadcast,
        is_active: active,
        is_listening: not broadcast,
        server_config: server_config,
        server_pid: server_pid,
        listener_id: listener_id,
        listener_socket: listener_socket,
        listener_span: listener_span,
        local_info: {ip, port}
      }
      
      # Start listening immediately for non-broadcast mode
      if not broadcast do
        Process.send_after(self(), :start_listening, 0)
      end
      
      {:ok, state}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_info(:start_listening, %{listener_socket: listener_socket} = state) do
    if state.is_listening do
      {:noreply, state}
    else
      case Abyss.Transport.UDP.getopts(listener_socket, [:active]) do
        {:ok, [{:active, false}]} ->
          Abyss.Telemetry.span_event(state.listener_span, :ready, %{}, %{
            listener_id: state.listener_id,
            listener_socket: state.listener_socket,
            local_info: state.local_info
          })

          Process.send_after(self(), :do_recv, 0)
          {:noreply, state |> Map.put(:is_listening, true)}

        {:ok, [active: true]} ->
          {:noreply, state}
      end
    end
  end

  def handle_info({:udp, socket, ip, port, data}, %{listener_span: listener_span} = state) do
    start_time = Abyss.Telemetry.monotonic_time()

    connection_span =
      Abyss.Telemetry.start_child_span(
        listener_span,
        :connection,
        %{monotonic_time: start_time},
        %{remote_address: ip, remote_port: port}
      )

    Abyss.Connection.start_active(
      state.server_pid,
      self(),
      socket,
      {ip, port, data},
      state.server_config,
      connection_span
    )

    {:noreply, state}
  end

  def handle_info(
        :do_recv,
        %{listener_span: listener_span, listener_socket: listener_socket} = state
      ) do
    Abyss.Telemetry.untimed_span_event(state.listener_span, :waiting, %{}, %{
      listener_id: state.listener_id,
      listener_socket: state.listener_socket,
      local_info: state.local_info
    })

    case Abyss.Transport.UDP.recv(listener_socket, 0, :infinity) do
      {:ok, {ip, port, data}} ->
        Abyss.Telemetry.untimed_span_event(state.listener_span, :receiving, %{}, %{
          listener_id: state.listener_id,
          listener_socket: state.listener_socket,
          local_info: state.local_info
        })

        start_time = Abyss.Telemetry.monotonic_time()

        connection_span =
          Abyss.Telemetry.start_child_span(
            listener_span,
            :connection,
            %{monotonic_time: start_time},
            %{remote_address: ip, remote_port: port}
          )

        Abyss.Connection.start(
          state.server_pid,
          self(),
          listener_socket,
          {ip, port, data},
          state.server_config,
          connection_span
        )

        Process.send_after(self(), :do_recv, 0)

        {:noreply, state}

      {:ok, {ip, port, _anc_data, data}} ->
        Abyss.Telemetry.untimed_span_event(state.listener_span, :receiving, %{}, %{
          listener_id: state.listener_id,
          listener_socket: state.listener_socket,
          local_info: state.local_info
        })

        start_time = Abyss.Telemetry.monotonic_time()

        connection_span =
          Abyss.Telemetry.start_child_span(
            listener_span,
            :connection,
            %{monotonic_time: start_time},
            %{remote_address: ip, remote_port: port}
          )

        Abyss.Connection.start(
          state.server_pid,
          self(),
          listener_socket,
          {ip, port, data},
          state.server_config,
          connection_span
        )

        Process.send_after(self(), :do_recv, 0)

        {:noreply, state}

      {:error, reason} ->
        Abyss.Telemetry.span_event(listener_span, :recv_error, %{
          reason: reason,
          listener_socket: listener_socket
        })

        {:stop, reason, state}
    end
  end

  def handle_info(:show_socket, state) do
    Process.send_after(self(), :show_socket, :timer.seconds(5))

    IO.inspect(
      :inet.getopts(state.listener_socket, [
        :active,
        :reuseaddr,
        :nodelay,
        :recbuf,
        :sndbuf,
        :mode,
        :reuseport,
        :tos,
        :ttl,
        :reuseport_lb,
        :debug,
        :buffer,
        :header
      ])
    )

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_continue(
        :listening,
        %{listener_span: listener_span, listener_socket: listener_socket} = state
      ) do
    Abyss.Telemetry.untimed_span_event(state.listener_span, :waiting, %{}, %{
      listener_id: state.listener_id,
      listener_socket: state.listener_socket,
      local_info: state.local_info
    })

    case Abyss.Transport.UDP.recv(listener_socket, 0, :infinity) do
      {:ok, recv_data} ->
        {ip, port, anc_data} =
          case recv_data do
            {ip, port, anc_data, _data} ->
              {ip, port, anc_data}

            {ip, port, _data} ->
              {ip, port, nil}
          end

        Abyss.Telemetry.untimed_span_event(state.listener_span, :receiving, %{}, %{
          listener_id: state.listener_id,
          listener_socket: state.listener_socket,
          local_info: state.local_info
        })

        start_time = Abyss.Telemetry.monotonic_time()

        connection_span =
          Abyss.Telemetry.start_child_span(
            listener_span,
            :connection,
            %{monotonic_time: start_time},
            %{remote_address: ip, remote_port: port, anc_data: anc_data}
          )

        Abyss.Connection.start(
          state.server_pid,
          self(),
          listener_socket,
          recv_data,
          state.server_config,
          connection_span
        )

        {:noreply, state, {:continue, :listening}}

      {:error, reason} ->
        Abyss.Telemetry.span_event(listener_span, :recv_error, %{
          reason: reason,
          listener_socket: listener_socket
        })

        {:stop, reason, state}
    end
  end

  @impl GenServer
  @spec handle_call(:listener_info | :socket_info, any, state) ::
          {:reply,
           Abyss.Transport.socket_info()
           | {Abyss.Transport.listener_socket(), Abyss.Telemetry.t()}, state}
  def handle_call(:listener_info, _from, state) do
    {:reply, state.local_info, state}
  end

  def handle_call(:socket_info, _from, state),
    do: {:reply, {state.listener_socket, state.listener_span}, state}

  @impl GenServer
  @spec terminate(reason, state) :: :ok
        when reason: :normal | :shutdown | {:shutdown, term} | term
  def terminate(_reason, state) do
    Abyss.Transport.UDP.close(state.listener_socket)
    Abyss.Telemetry.stop_span(state.listener_span)
  end
end
