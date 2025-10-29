defmodule Abyss.Listener do
  @moduledoc """
  UDP listener process that accepts incoming packets and creates handler processes.

  Each listener process is responsible for:
  - Binding to a UDP port and receiving packets
  - Applying rate limiting and packet size validation
  - Creating handler processes for valid packets
  - Managing connection lifecycle and telemetry events

  ## Modes of Operation

  - **Regular Mode**: Passively receives packets and creates handler processes
  - **Broadcast Mode**: Actively receives packets with `active: true`

  ## Security Features

  - **Rate Limiting**: Token bucket algorithm per IP address
  - **Packet Size Validation**: Rejects oversized packets
  - **Telemetry Events**: Comprehensive monitoring and logging

  ## Process Flow

  1. Initialize UDP socket with transport options
  2. Start receiving packets (passive or active mode)
  3. Apply security checks (rate limiting, packet size)
  4. Create handler process via `Abyss.Connection`
  5. Emit telemetry events for monitoring

  This module is primarily used internally by `Abyss.ListenerPool`.
  """

  use GenServer, restart: :transient

  @typedoc """
  Internal state of a listener process.
  """
  @type state :: %{
          is_active: boolean(),
          is_listening: boolean(),
          server_pid: pid(),
          server_config: Abyss.ServerConfig.t(),
          listener_id: binary(),
          listener_socket: Abyss.Transport.socket(),
          listener_span: Abyss.Telemetry.t(),
          local_info: Abyss.Transport.socket_info(),
          transport: module()
        }

  @doc """
  Start a listener process.

  ## Parameters
  - `id` - Unique identifier for this listener
  - `server_pid` - PID of the server supervisor
  - `config` - Server configuration

  ## Returns
  - Standard GenServer start result
  """
  @spec start_link({id :: binary(), server_pid :: pid(), Abyss.ServerConfig.t()}) ::
          GenServer.on_start()
  def start_link({id, server_pid, config}),
    do: GenServer.start_link(__MODULE__, {id, server_pid, config})

  @doc """
  Stop a listener process gracefully.

  ## Parameters
  - `server` - The listener process PID or name
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server), do: GenServer.stop(server)

  @doc """
  Get information about the listener's local socket endpoint.

  ## Parameters
  - `server` - The listener process PID or name

  ## Returns
  - `{ip_address, port}` tuple with local endpoint information
  """
  @spec listener_info(GenServer.server()) :: Abyss.Transport.socket_info()
  def listener_info(server), do: GenServer.call(server, :listener_info)

  @doc """
  Get the listener's socket and telemetry span.

  ## Parameters
  - `server` - The listener process PID or name

  ## Returns
  - `{socket, telemetry_span}` tuple
  """
  @spec socket_info(GenServer.server()) ::
          {Abyss.Transport.listener_socket(), Abyss.Telemetry.t()}
  def socket_info(server), do: GenServer.call(server, :socket_info)

  @impl GenServer
  @spec init({listener_id :: neg_integer(), server_pid :: pid(), Abyss.ServerConfig.t()}) ::
          {:ok, map()} | {:stop, term()}
  def init({listener_id, server_pid, server_config}) do
    broadcast = server_config.broadcast

    transport_options =
      if broadcast do
        server_config.transport_options
        |> Keyword.put(:active, true)
        |> Keyword.put(:broadcast, true)
        |> Keyword.put(:recbuf, server_config.udp_buffer_size)
        |> Keyword.put(:sndbuf, server_config.udp_buffer_size)
      else
        server_config.transport_options
        |> Keyword.put(:active, false)
        |> Keyword.put(:broadcast, false)
        |> Keyword.put(:recbuf, server_config.udp_buffer_size)
        |> Keyword.put(:sndbuf, server_config.udp_buffer_size)
      end

    transport = server_config.transport_module

    with {:ok, listener_socket} <-
           transport.listen(
             server_config.port,
             transport_options
           ),
         {:ok, {ip, port}} <-
           :inet.sockname(listener_socket) do
      active =
        case transport.getopts(listener_socket, [:active]) do
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
        local_info: {ip, port},
        transport: transport
      }

      # Start listening immediately for non-broadcast mode
      _ =
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
  def handle_info(
        :start_listening,
        %{listener_socket: listener_socket, transport: transport} = state
      ) do
    if state.is_listening do
      {:noreply, state}
    else
      case transport.getopts(listener_socket, [:active]) do
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
    # Check rate limiting
    if state.server_config.rate_limit_enabled and not Abyss.RateLimiter.allow_packet?(ip) do
      Abyss.Telemetry.span_event(listener_span, :rate_limit_exceeded, %{
        remote_address: ip,
        remote_port: port
      })

      {:noreply, state}
    else
      # Check packet size
      if byte_size(data) > state.server_config.max_packet_size do
        Abyss.Telemetry.span_event(listener_span, :packet_too_large, %{
          remote_address: ip,
          remote_port: port,
          packet_size: byte_size(data),
          max_size: state.server_config.max_packet_size
        })

        {:noreply, state}
      else
        start_time = Abyss.Telemetry.monotonic_time()

        # Track connection acceptance
        Abyss.Telemetry.track_connection_accepted()

        connection_span =
          Abyss.Telemetry.start_child_span_with_sampling(
            listener_span,
            :connection,
            %{monotonic_time: start_time},
            %{remote_address: ip, remote_port: port, accept_start_time: start_time},
            sample_rate: state.server_config.connection_telemetry_sample_rate
          )

        _ =
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
    end
  end

  def handle_info(
        :do_recv,
        %{listener_span: listener_span, listener_socket: listener_socket, transport: transport} =
          state
      ) do
    Abyss.Telemetry.untimed_span_event(state.listener_span, :waiting, %{}, %{
      listener_id: state.listener_id,
      listener_socket: state.listener_socket,
      local_info: state.local_info
    })

    case transport.recv(listener_socket, 0, :infinity) do
      {:ok, {ip, port, data}} ->
        handle_received_packet(ip, port, data, listener_socket, state)

      {:ok, {ip, port, _anc_data, data}} ->
        handle_received_packet(ip, port, data, listener_socket, state)

      {:error, reason} ->
        Abyss.Telemetry.span_event(listener_span, :recv_error, %{
          reason: reason,
          listener_socket: listener_socket
        })

        {:stop, reason, state}
    end
  end

  def handle_info({:retry_connection, retry_args}, state) do
    _ = Abyss.Connection.retry_start(retry_args)
    {:noreply, state}
  end

  def handle_info({:retry_active_connection, retry_args}, state) do
    _ = Abyss.Connection.retry_start_active(retry_args)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_continue(
        :listening,
        %{listener_span: listener_span, listener_socket: listener_socket, transport: transport} =
          state
      ) do
    Abyss.Telemetry.untimed_span_event(state.listener_span, :waiting, %{}, %{
      listener_id: state.listener_id,
      listener_socket: state.listener_socket,
      local_info: state.local_info
    })

    case transport.recv(listener_socket, 0, :infinity) do
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

        _ =
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

  # Private helper functions

  defp handle_received_packet(ip, port, data, listener_socket, state) do
    %{listener_span: listener_span} = state

    Abyss.Telemetry.untimed_span_event(state.listener_span, :receiving, %{}, %{
      listener_id: state.listener_id,
      listener_socket: state.listener_socket,
      local_info: state.local_info
    })

    cond do
      state.server_config.rate_limit_enabled and not Abyss.RateLimiter.allow_packet?(ip) ->
        Abyss.Telemetry.span_event(listener_span, :rate_limit_exceeded, %{
          remote_address: ip,
          remote_port: port
        })

        _ = Process.send_after(self(), :do_recv, 0)
        {:noreply, state}

      byte_size(data) > state.server_config.max_packet_size ->
        Abyss.Telemetry.span_event(listener_span, :packet_too_large, %{
          remote_address: ip,
          remote_port: port,
          packet_size: byte_size(data),
          max_size: state.server_config.max_packet_size
        })

        _ = Process.send_after(self(), :do_recv, 0)
        {:noreply, state}

      true ->
        start_time = Abyss.Telemetry.monotonic_time()

        # Track connection acceptance
        Abyss.Telemetry.track_connection_accepted()

        connection_span =
          Abyss.Telemetry.start_child_span_with_sampling(
            listener_span,
            :connection,
            %{monotonic_time: start_time},
            %{remote_address: ip, remote_port: port, accept_start_time: start_time},
            sample_rate: state.server_config.connection_telemetry_sample_rate
          )

        _ =
          Abyss.Connection.start(
            state.server_pid,
            self(),
            listener_socket,
            {ip, port, data},
            state.server_config,
            connection_span
          )

        _ = Process.send_after(self(), :do_recv, 0)

        {:noreply, state}
    end
  end

  @impl GenServer
  @spec terminate(reason, state) :: :ok
        when reason: :normal | :shutdown | {:shutdown, term} | term
  def terminate(_reason, state) do
    state.transport.close(state.listener_socket)
    Abyss.Telemetry.stop_span(state.listener_span)
  end
end
