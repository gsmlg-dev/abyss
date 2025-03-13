defmodule DumpMDNS do
  use Abyss.Handler

  def handle_data(recv_data, state) do
    {ip, port, data} = recv_data
    IO.puts("📩 Received UDP message from #{:inet.ntoa(ip)}:#{port} ->")
    case :inet_dns.decode(data) do
      {:ok, message} ->
        IO.inspect(message, limit: :infinity)
      {:error, error} ->
        IO.inspect({:error, error}, limit: :infinity)
    end
    {:close, state}
  end
end
