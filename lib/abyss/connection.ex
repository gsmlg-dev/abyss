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
    do_start_with_backoff(
      sup_pid,
      child_spec,
      listener_pid,
      listener_socket,
      recv_data,
      server_config,
      connection_span,
      retries
    )
  end

  defp do_start_with_backoff(
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
        send(pid, {:new_connection, listener_socket, recv_data})
        :ok

      {:error, :max_children} when retries > 0 ->
        # Exponential backoff with jitter
        base_delay = server_config.max_connections_retry_wait
        backoff_multiplier = :math.pow(1.5, server_config.max_connections_retry_count - retries)
        delay = round(base_delay * backoff_multiplier)
        # 25% jitter
        jitter = :rand.uniform(div(delay, 4))

        # Use Task for non-blocking retry to avoid blocking the listener
        Task.start(fn ->
          Process.sleep(delay + jitter)

          do_start_with_backoff(
            sup_pid,
            child_spec,
            listener_pid,
            listener_socket,
            recv_data,
            server_config,
            connection_span,
            retries - 1
          )
        end)

        {:retry, :connection_limit}

      {:error, :max_children} ->
        # Log connection limit exceeded via telemetry
        :telemetry.execute(
          [:abyss, :connection, :limit_exceeded],
          %{retries_attempted: server_config.max_connections_retry_count - retries},
          %{listener_pid: listener_pid, socket: listener_socket}
        )

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
    do_start_active_with_backoff(
      sup_pid,
      child_spec,
      listener_pid,
      listener_socket,
      recv_data,
      server_config,
      connection_span,
      retries
    )
  end

  defp do_start_active_with_backoff(
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
        send(pid, {:new_connection, listener_socket, recv_data})
        :ok

      {:error, :max_children} when retries > 0 ->
        # Exponential backoff with jitter
        base_delay = server_config.max_connections_retry_wait
        backoff_multiplier = :math.pow(1.5, server_config.max_connections_retry_count - retries)
        delay = round(base_delay * backoff_multiplier)
        # 25% jitter
        jitter = :rand.uniform(div(delay, 4))

        # Use Task for non-blocking retry to avoid blocking the listener
        Task.start(fn ->
          Process.sleep(delay + jitter)

          do_start_active_with_backoff(
            sup_pid,
            child_spec,
            listener_pid,
            listener_socket,
            recv_data,
            server_config,
            connection_span,
            retries - 1
          )
        end)

        {:retry, :connection_limit}

      {:error, :max_children} ->
        # Log connection limit exceeded via telemetry
        :telemetry.execute(
          [:abyss, :connection, :limit_exceeded],
          %{retries_attempted: server_config.max_connections_retry_count - retries},
          %{listener_pid: listener_pid, socket: listener_socket}
        )

        {:error, :too_many_connections}

      other ->
        other
    end
  end
end
