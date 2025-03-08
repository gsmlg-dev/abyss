defmodule Echo do
  use Abyss.Handler

  def handle_data(
        data,
        %{socket: listener_socket} = state
      ) do
    {ip, port, data} = data
    IO.puts("📩 Received UDP message from #{:inet.ntoa(ip)}:#{port} -> #{inspect(data)}")

    msg = "✅ Processed: #{data}"

    Abyss.Transport.UDP.send(listener_socket, ip, port, msg)
    {:close, state}
  end
end
