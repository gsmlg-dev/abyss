defmodule Abyss.Worker do
  use GenServer

  ## Public API
  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  ## Server Callbacks
  def init(_) do
    {:ok, %{}}
  end

  def handle_cast({:process_packet, socket, ip, port, data}, state) do
    # Simulate processing delay
    Process.sleep(100)
    response = "✅ Processed: #{data}"

    # Send response back
    :gen_udp.send(socket, ip, port, response)

    IO.puts(
      "📤 Sent response at (#{inspect(self())}) to #{:inet.ntoa(ip)}:#{port} -> #{inspect(response)}"
    )

    {:noreply, state}
  end
end
