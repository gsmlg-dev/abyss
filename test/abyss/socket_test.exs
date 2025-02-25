defmodule Abyss.SocketTest do
  use ExUnit.Case, async: true

  use Machete

  def gen_udp_setup(_context) do
    {:ok, %{client_mod: :gen_udp, server_opts: []}}
  end

  defmodule Echo do
    use Abyss.Handler

    @impl Abyss.Handler
    def handle_connection(socket, state) do
      {:ok, data} = Abyss.Socket.recv(socket, 0)
      Abyss.Socket.send(socket, data)
      {:close, state}
    end
  end

  defmodule Sendfile do
    use Abyss.Handler

    @impl Abyss.Handler
    def handle_connection(socket, state) do
      Abyss.Socket.sendfile(socket, Path.join(__DIR__, "../support/sendfile"), 0, 6)
      Abyss.Socket.sendfile(socket, Path.join(__DIR__, "../support/sendfile"), 1, 3)
      send(state[:test_pid], Process.info(self(), :monitored_by))
      {:close, state}
    end
  end

  defmodule Closer do
    use Abyss.Handler

    @impl Abyss.Handler
    def handle_connection(_socket, state) do
      {:close, state}
    end
  end

  defmodule Info do
    use Abyss.Handler

    @impl Abyss.Handler
    def handle_connection(socket, state) do
      {:ok, peer_info} = Abyss.Socket.peername(socket)
      {:ok, local_info} = Abyss.Socket.sockname(socket)
      negotiated_protocol = Abyss.Socket.negotiated_protocol(socket)

      Abyss.Socket.send(
        socket,
        "#{inspect([local_info, peer_info, negotiated_protocol])}"
      )

      {:close, state}
    end
  end
end
