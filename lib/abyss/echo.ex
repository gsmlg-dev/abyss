defmodule Abyss.Echo do
  use GenServer, restart: :temporary

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl GenServer
  def init({connection_span, server_config}) do
    {:ok, %{connection_span: connection_span, server_config: server_config}}
  end

  @impl GenServer
  def handle_info(
        {:new_connection, listener_pid, listener_socket, ip, port, data},
        state
      ) do
    state = state
      |> Map.put(:listener_pid, listener_pid)
      |> Map.put(:listener_socket, listener_socket)

    IO.puts("📩 Received UDP message from #{:inet.ntoa(ip)}:#{port} -> #{inspect(data)}")

    msg = "✅ Processed: #{data}"

    Abyss.Transport.UDP.send(listener_socket, ip, port, msg)

    # {:noreply, state, :timer.seconds(15)}
    {:stop, :normal, state}
  end
  def handle_info(
        {:new_connection, listener_pid, listener_socket, ip, port, data, anc_data},
        state
      ) do
    state = state
      |> Map.put(:listener_pid, listener_pid)
      |> Map.put(:listener_socket, listener_socket)

    IO.puts("📩 Received UDP message from #{:inet.ntoa(ip)}:#{port} (#{inspect(anc_data)}) -> #{inspect(data)}")

    msg = "✅ Processed: #{data}"

    Abyss.Transport.UDP.send(listener_socket, ip, port, msg)

    # {:noreply, state, :timer.seconds(15)}
    {:stop, :normal, state}
  end
  def handle_info(:timeout, state) do
    {:stop, :timeout, state}
  end

  @impl GenServer
  def terminate(reason, %{connection_span: connection_span, listener_pid: listener_pid, listener_socket: listener_socket} = _state) do
    Abyss.Transport.UDP.controlling_process(listener_socket, listener_pid)

    Abyss.Telemetry.stop_span(connection_span, %{}, %{reason: reason})

    :ok
  end
end
