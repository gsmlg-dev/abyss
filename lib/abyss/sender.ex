defmodule Abyss.Sender do
  @moduledoc false

  use GenServer

  @type state :: %{
          server_pid: pid(),
          sender_socket: Abyss.Transport.socket(),
          sender_span: Abyss.Telemetry.t(),
          local_info: Abyss.Transport.socket_info()
        }

  @spec start_link({id :: pos_integer(), server_pid :: pid(), Abyss.ServerConfig.t()}) ::
          GenServer.on_start()
  def start_link({id, server_pid, config}),
    do: GenServer.start_link(__MODULE__, {id, server_pid, config})

  @spec stop(GenServer.server()) :: :ok
  def stop(server), do: GenServer.stop(server)

  @spec sender_info(GenServer.server()) :: Abyss.Transport.socket_info()
  def sender_info(server), do: GenServer.call(server, :sender_info)

  @spec socket_info(GenServer.server()) ::
          {Abyss.Transport.socket(), Abyss.Telemetry.t()}
  def socket_info(server), do: GenServer.call(server, :socket_info)

  @impl GenServer
  @spec init({sender_id :: neg_integer(), server_pid :: pid(), Abyss.ServerConfig.t()}) ::
          {:ok, state} | {:stop, term}
  def init({sender_id, server_pid, server_config}) do
    with {:ok, sender_socket} <-
           Abyss.Transport.UDP.listen(
             server_config.port,
             server_config.transport_options
           ),
         {:ok, {ip, port}} <-
           :inet.sockname(sender_socket) do
      span_metadata = %{
        sender_id: sender_id,
        handler: server_config.handler_module,
        local_address: ip,
        local_port: port,
        transport_options: server_config.transport_options
      }

      sender_span = Abyss.Telemetry.start_span(:sender, %{}, span_metadata)

      {:ok,
       %{
         server_pid: server_pid,
         sender_socket: sender_socket,
         local_info: {ip, port},
         sender_span: sender_span
       }}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  @spec handle_call(:sender_info | :socket_info, any, state) ::
          {:reply,
           Abyss.Transport.socket_info()
           | {Abyss.Transport.socket(), Abyss.Telemetry.t()}, state}
  def handle_call(:sender_info, _from, state), do: {:reply, state.local_info, state}

  def handle_call(:socket_info, _from, state),
    do: {:reply, {state.sender_socket, state.sender_span}, state}

  @impl GenServer
  @spec terminate(reason, state) :: :ok
        when reason: :normal | :shutdown | {:shutdown, term} | term
  def terminate(_reason, state), do: Abyss.Telemetry.stop_span(state.sender_span)
end
