defmodule Abyss.Listener do
  @moduledoc false

  use GenServer

  @type state :: %{
          server_pid: pid(),
          listener_socket: Abyss.Transport.socket(),
          listener_span: Abyss.Telemetry.t(),
          local_info: Abyss.Transport.socket_info()
        }

  @spec start_link({id :: pos_integer(), server_pid :: pid(), Abyss.ServerConfig.t()}) ::
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
    with {:ok, listener_socket} <-
           Abyss.Transport.UDP.listen(
             server_config.port,
             server_config.transport_options
           ),
         {:ok, {ip, port}} <-
           :inet.sockname(listener_socket) do
      span_metadata = %{
        listener_id: listener_id,
        handler: server_config.handler_module,
        local_address: ip,
        local_port: port,
        transport_options: server_config.transport_options
      }

      listener_span = Abyss.Telemetry.start_span(:listener, %{}, span_metadata)

      {:ok,
       %{
         server_pid: server_pid,
         listener_socket: listener_socket,
         local_info: {ip, port},
         listener_span: listener_span
       }}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_info(:start_listening, state) do

    {:noreply, state, {:continue, :listening}}
  end

  def handle_continue(:listening, state) do
    case Abyss.Transport.UDP.recv(state.listener_socket, 0) do
      {:ok, {socket, ip, port, data}} ->
        send(state.server_pid, {:new_connection, socket, ip, port, data})
        {:noreply, state, {:continue, :listening}}
      {:ok, {socket, ip, port, anc_data, data}} ->
        send(state.server_pid, {:new_connection, socket, ip, port, data, anc_data})
        {:noreply, state, {:continue, :listening}}
      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  @impl GenServer
  @spec handle_call(:listener_info | :socket_info, any, state) ::
          {:reply,
           Abyss.Transport.socket_info()
           | {Abyss.Transport.listener_socket(), Abyss.Telemetry.t()}, state}
  def handle_call(:listener_info, _from, state), do: {:reply, state.local_info, state}

  def handle_call(:socket_info, _from, state),
    do: {:reply, {state.listener_socket, state.listener_span}, state}

  @impl GenServer
  @spec terminate(reason, state) :: :ok
        when reason: :normal | :shutdown | {:shutdown, term} | term
  def terminate(_reason, state), do: Abyss.Telemetry.stop_span(state.listener_span)

end
