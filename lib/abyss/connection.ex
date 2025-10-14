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
        # into the connection supervisor. Schedule a non-blocking retry after the configured wait time
        retry_args = [
          sup_pid, child_spec, listener_pid, listener_socket, recv_data, server_config, connection_span, retries - 1
        ]

        # Use Process.send_after to schedule the retry without blocking the current process
        Process.send_after(
          listener_pid,
          {:retry_connection, retry_args},
          server_config.max_connections_retry_wait
        )

        :ok

      {:error, :max_children} ->
        # We gave up trying to find room for this connection in our supervisor.
        # Close the raw socket here and let the acceptor process handle propagating the error
        {:error, :too_many_connections}

      other ->
        other
    end
  end

  @spec start_active(
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
  def start_active(
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
    do_start_active(
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

  defp do_start_active(
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
        send(
          pid,
          {:new_connection, listener_socket, recv_data}
        )

        :ok

      {:error, :max_children} when retries > 0 ->
        # We're in a tricky spot here; we have a client connection in hand, but no room to put it
        # into the connection supervisor. Schedule a non-blocking retry after the configured wait time
        retry_args = [
          sup_pid, child_spec, listener_pid, listener_socket, recv_data, server_config, connection_span, retries - 1
        ]

        # Use Process.send_after to schedule the retry without blocking the current process
        Process.send_after(
          listener_pid,
          {:retry_active_connection, retry_args},
          server_config.max_connections_retry_wait
        )

        :ok

      {:error, :max_children} ->
        # We gave up trying to find room for this connection in our supervisor.
        # Close the raw socket here and let the acceptor process handle propagating the error
        {:error, :too_many_connections}

      other ->
        other
    end
  end

  @doc """
  Handle a retry message for regular connection start.
  This should be called from the listener process when receiving a {:retry_connection, args} message.
  """
  def retry_start([sup_pid, child_spec, listener_pid, listener_socket, recv_data, server_config, connection_span, retries]) do
    do_start(sup_pid, child_spec, listener_pid, listener_socket, recv_data, server_config, connection_span, retries)
  end

  @doc """
  Handle a retry message for active connection start.
  This should be called from the listener process when receiving a {:retry_active_connection, args} message.
  """
  def retry_start_active([sup_pid, child_spec, listener_pid, listener_socket, recv_data, server_config, connection_span, retries]) do
    do_start_active(sup_pid, child_spec, listener_pid, listener_socket, recv_data, server_config, connection_span, retries)
  end
end
