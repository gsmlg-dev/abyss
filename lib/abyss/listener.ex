defmodule Abyss.Listener do
  @moduledoc false

  # use GenServer, restart: :transient
  use GenServer

  @type state :: %{
          listener_socket: :gen_udp.socket(),
          listener_span: Abyss.Telemetry.t(),
          local_info: Abyss.Transport.socket_info()
        }

  @spec start_link(Abyss.ServerConfig.t()) :: GenServer.on_start()
  def start_link(config), do: GenServer.start_link(__MODULE__, config)

  @spec stop(GenServer.server()) :: :ok
  def stop(server), do: GenServer.stop(server)

  @spec listener_info(GenServer.server()) :: Abyss.Transport.socket_info()
  def listener_info(server), do: GenServer.call(server, :listener_info)

  @spec acceptor_info(GenServer.server()) ::
          {Abyss.Transport.listener_socket(), Abyss.Telemetry.t()}
  def acceptor_info(server), do: GenServer.call(server, :acceptor_info)

  @impl GenServer
  @spec init(Abyss.ServerConfig.t()) :: {:ok, state} | {:stop, term}
  def init(%Abyss.ServerConfig{} = server_config) do
    with {:ok, listener_socket} <-
           :gen_udp.open(
             server_config.port,
             server_config.transport_options
           ),
         {:ok, {ip, port}} <-
           :inet.sockname(listener_socket) do
      span_metadata = %{
        handler: server_config.handler_module,
        local_address: ip,
        local_port: port,
        transport_options: server_config.transport_options
      }

      listener_span = Abyss.Telemetry.start_span(:listener, %{}, span_metadata)

      {:ok,
       %{listener_socket: listener_socket, local_info: {ip, port}, listener_span: listener_span}}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  @spec handle_call(:listener_info | :acceptor_info, any, state) ::
          {:reply,
           Abyss.Transport.socket_info()
           | {Abyss.Transport.listener_socket(), Abyss.Telemetry.t()}, state}
  def handle_call(:listener_info, _from, state), do: {:reply, state.local_info, state}

  def handle_call(:acceptor_info, _from, state),
    do: {:reply, {state.listener_socket, state.listener_span}, state}

  @impl GenServer
  @spec terminate(reason, state) :: :ok
        when reason: :normal | :shutdown | {:shutdown, term} | term
  def terminate(_reason, state), do: Abyss.Telemetry.stop_span(state.listener_span)
end
