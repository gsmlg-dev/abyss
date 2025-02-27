defmodule Abyss.Acceptor do
  @moduledoc false

  use Task, restart: :transient

  @spec start_link(
          {server :: Supervisor.supervisor(), parent :: Supervisor.supervisor(),
           Abyss.ServerConfig.t()}
        ) :: {:ok, pid()}
  def start_link(arg), do: Task.start_link(__MODULE__, :run, [arg])

  @spec run(
          {server :: Supervisor.supervisor(), parent :: Supervisor.supervisor(),
           Abyss.ServerConfig.t()}
        ) :: no_return
  def run(
        {server_pid, parent_pid,
         %Abyss.ServerConfig{transport_module: transport_module} = server_config}
      )
      when transport_module == Abyss.Transports.UDP do
    listener_pid = Abyss.Server.listener_pid(server_pid)
    {listener_socket, listener_span} = Abyss.Listener.acceptor_info(listener_pid)
    connection_sup_pid = Abyss.AcceptorSupervisor.connection_sup_pid(parent_pid)
    acceptor_span = Abyss.Telemetry.start_child_span(listener_span, :acceptor)
    recv(listener_socket, connection_sup_pid, server_config, acceptor_span, 0)
  end

  def run({server_pid, parent_pid, %Abyss.ServerConfig{} = server_config}) do
    listener_pid = Abyss.Server.listener_pid(server_pid)
    {listener_socket, listener_span} = Abyss.Listener.acceptor_info(listener_pid)
    connection_sup_pid = Abyss.AcceptorSupervisor.connection_sup_pid(parent_pid)
    acceptor_span = Abyss.Telemetry.start_child_span(listener_span, :acceptor)
    accept(listener_socket, connection_sup_pid, server_config, acceptor_span, 0)
  end

  defp accept(listener_socket, connection_sup_pid, server_config, span, count) do
    with {:ok, socket} <- server_config.transport_module.accept(listener_socket),
         :ok <- Abyss.Connection.start(connection_sup_pid, socket, server_config, span) do
      accept(listener_socket, connection_sup_pid, server_config, span, count + 1)
    else
      {:error, :too_many_connections} ->
        Abyss.Telemetry.span_event(span, :spawn_error)
        accept(listener_socket, connection_sup_pid, server_config, span, count + 1)

      {:error, :econnaborted} ->
        Abyss.Telemetry.span_event(span, :econnaborted)
        accept(listener_socket, connection_sup_pid, server_config, span, count + 1)

      {:error, reason} when reason in [:closed, :einval] ->
        Abyss.Telemetry.stop_span(span, %{connections: count})

      {:error, reason} ->
        Abyss.Telemetry.stop_span(span, %{connections: count}, %{error: reason})
        raise "Unexpected error in accept: #{inspect(reason)}"
    end
  end

  defp recv(listener_socket, connection_sup_pid, server_config, span, count) do
    with {:ok, recv_data} <- server_config.transport_module.recv(listener_socket, 0),
         :ok <- Abyss.Connection.start(connection_sup_pid, recv_data, server_config, span) do
      recv(listener_socket, connection_sup_pid, server_config, span, count + 1)
    else
      {:error, :too_many_connections} ->
        Abyss.Telemetry.span_event(span, :spawn_error)
        recv(listener_socket, connection_sup_pid, server_config, span, count + 1)

      {:error, :econnaborted} ->
        Abyss.Telemetry.span_event(span, :econnaborted)
        recv(listener_socket, connection_sup_pid, server_config, span, count + 1)

      {:error, reason} when reason in [:closed, :einval] ->
        Abyss.Telemetry.stop_span(span, %{connections: count})

      {:error, reason} ->
        Abyss.Telemetry.stop_span(span, %{connections: count}, %{error: reason})
        raise "Unexpected error in accept: #{inspect(reason)}"
    end
  end
end
