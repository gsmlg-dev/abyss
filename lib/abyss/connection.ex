defmodule Abyss.Connection do
  @moduledoc false

  @spec start(
          Supervisor.supervisor(),
          pid(),
          Abyss.Transport.socket(),
          Abyss.Transport.recv_data(),
          Abyss.ServerConfig.t(),
          Abyss.Telemetry.t()
        ) ::
          :ignore
          | :ok
          | {:ok, pid, info :: term}
          | {:error, :too_many_connections | {:already_started, pid} | term}
  def start(
        sup_pid,
        listener_pid,
        listener_socket,
        recv_data,
        %Abyss.ServerConfig{} = server_config,
        connection_span
      ) do
    # This is a multi-step process since we need to do a bit of work from within
    # the process which owns the socket (us, at this point).
    # {ip, port, _data} = recv_data

    # Start by defining the worker process which will eventually handle this socket
    child_spec =
      {server_config.handler_module,
       {connection_span, server_config, listener_pid, listener_socket}}
      |> Supervisor.child_spec(
        # id: {:connection, ip, port},
        shutdown: server_config.shutdown_timeout
      )

    connection_sup_pid = Abyss.Server.connection_sup_pid(sup_pid)

    # Then try to create it
    do_start(
      connection_sup_pid,
      child_spec,
      listener_pid,
      listener_socket,
      recv_data,
      server_config,
      connection_span,
      server_config.max_connections_retry_count
    )
  end

  defp do_start(
         sup_pid,
         child_spec,
         listener_pid,
         listener_socket,
         recv_data,
         server_config,
         connection_span,
         retries
       ) do
    case DynamicSupervisor.start_child(sup_pid, child_spec) do
      {:ok, pid} ->
        Abyss.Transport.UDP.controlling_process(listener_socket, pid)

        send(
          pid,
          {:new_connection, listener_socket, recv_data}
        )

        :ok

      {:error, :max_children} when retries > 0 ->
        # We're in a tricky spot here; we have a client connection in hand, but no room to put it
        # into the connection supervisor. We try to wait a maximum number of times to see if any
        # room opens up before we give up
        Process.sleep(server_config.max_connections_retry_wait)

        do_start(
          sup_pid,
          child_spec,
          listener_pid,
          listener_socket,
          recv_data,
          server_config,
          connection_span,
          retries - 1
        )

      {:error, :max_children} ->
        # We gave up trying to find room for this connection in our supervisor.
        # Close the raw socket here and let the acceptor process handle propagating the error
        {:error, :too_many_connections}

      other ->
        other
    end
  end
end
