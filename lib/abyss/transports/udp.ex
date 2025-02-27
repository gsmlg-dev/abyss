defmodule Abyss.Transports.UDP do
  @moduledoc """
  Defines a `Abyss.Transport` implementation based on clear UDP sockets
  as provided by Erlang's `:gen_udp` module. For the most part, users of Thousand
  Island will only ever need to deal with this module via `transport_options`
  passed to `Abyss` at startup time. A complete list of such options
  is defined via the `t::gen_udp.open_option/0` type. This list can be somewhat
  difficult to decipher; by far the most common value to pass to this transport
  is the following:

  * `ip`:  The IP to listen on. Can be specified as:
    * `{1, 2, 3, 4}` for IPv4 addresses
    * `{1, 2, 3, 4, 5, 6, 7, 8}` for IPv6 addresses
    * `:loopback` for local loopback
    * `:any` for all interfaces (i.e.: `0.0.0.0`)
    * `{:local, "/path/to/socket"}` for a Unix domain socket. If this option is used,
      the `port` option *must* be set to `0`

  Unless overridden, this module uses the following default options:

  ```elixir
  backlog: 1024,
  nodelay: true,
  send_timeout: 30_000,
  send_timeout_close: true,
  reuseaddr: true
  ```

  The following options are required for the proper operation of Abyss
  and cannot be overridden:

  ```elixir
  mode: :binary,
  active: false
  ```
  """

  @type options() :: [:gen_udp.open_option()]
  @type listener_socket() :: :inet.socket()
  @type socket() :: :inet.socket()

  @behaviour Abyss.Transport

  @hardcoded_options [:binary, active: false]

  @impl Abyss.Transport
  @spec listen(:inet.port_number(), [:inet.inet_backend() | :gen_udp.open_option()]) ::
          Abyss.Transport.on_listen()
  def listen(port, user_options) do
    default_options = [
      reuseaddr: true
    ]

    # We can't use Keyword functions here because :gen_udp accepts non-keyword style options
    resolved_options =
      Enum.uniq_by(
        @hardcoded_options ++ user_options ++ default_options,
        fn
          {key, _} when is_atom(key) -> key
          key when is_atom(key) -> key
        end
      )

    :gen_udp.open(port, resolved_options)
  end

  @impl Abyss.Transport
  @spec accept(listener_socket()) :: Abyss.Transport.on_accept()
  def accept(listener_socket), do: {:ok, listener_socket}

  @impl Abyss.Transport
  @spec handshake(socket()) :: Abyss.Transport.on_handshake()
  def handshake(socket), do: {:ok, socket}

  @impl Abyss.Transport
  @spec upgrade(socket(), options()) :: Abyss.Transport.on_upgrade()
  def upgrade(_, _), do: {:error, :unsupported_upgrade}

  @impl Abyss.Transport
  @spec controlling_process(socket(), pid()) :: Abyss.Transport.on_controlling_process()
  def controlling_process(socket, pid) do
    :gen_udp.controlling_process(socket, pid)
  end

  @impl Abyss.Transport
  @spec recv(socket(), non_neg_integer(), timeout()) :: Abyss.Transport.on_recv()
  defdelegate recv(socket, length, timeout), to: :gen_udp

  @spec recv(socket(), non_neg_integer()) :: Abyss.Transport.on_recv()
  defdelegate recv(socket, length), to: :gen_udp

  @impl Abyss.Transport
  @spec send(socket(), iodata()) :: Abyss.Transport.on_send()
  defdelegate send(socket, data), to: :gen_udp

  @impl Abyss.Transport
  @spec sendfile(
          socket(),
          filename :: String.t(),
          offset :: non_neg_integer(),
          length :: non_neg_integer()
        ) :: Abyss.Transport.on_sendfile()
  def sendfile(socket, filename, offset, length) do
    case :file.open(filename, [:raw]) do
      {:ok, fd} ->
        try do
          :file.sendfile(fd, socket, offset, length, [])
        after
          :file.close(fd)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Abyss.Transport
  @spec getopts(socket(), Abyss.Transport.socket_get_options()) ::
          Abyss.Transport.on_getopts()
  defdelegate getopts(socket, options), to: :inet

  @impl Abyss.Transport
  @spec setopts(socket(), Abyss.Transport.socket_set_options()) ::
          Abyss.Transport.on_setopts()
  defdelegate setopts(socket, options), to: :inet

  @impl Abyss.Transport
  @spec shutdown(socket(), Abyss.Transport.way()) ::
          Abyss.Transport.on_shutdown()
  def shutdown(socket, _way), do: :gen_udp.close(socket)

  @impl Abyss.Transport
  @spec close(socket() | listener_socket()) :: :ok
  defdelegate close(socket), to: :gen_udp

  @impl Abyss.Transport
  @spec sockname(socket() | listener_socket()) :: Abyss.Transport.on_sockname()
  defdelegate sockname(socket), to: :inet

  @impl Abyss.Transport
  @spec peername(socket()) :: Abyss.Transport.on_peername()
  defdelegate peername(socket), to: :inet

  @impl Abyss.Transport
  @spec peercert(socket()) :: Abyss.Transport.on_peercert()
  def peercert(_socket), do: {:error, :not_secure}

  @impl Abyss.Transport
  @spec secure?() :: false
  def secure?, do: false

  @impl Abyss.Transport
  @spec getstat(socket()) :: Abyss.Transport.socket_stats()
  defdelegate getstat(socket), to: :inet

  @impl Abyss.Transport
  @spec negotiated_protocol(socket()) :: Abyss.Transport.on_negotiated_protocol()
  def negotiated_protocol(_socket), do: {:error, :protocol_not_negotiated}
end
