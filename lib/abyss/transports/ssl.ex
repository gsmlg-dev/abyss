defmodule Abyss.Transports.SSL do
  @moduledoc """
  Defines a `Abyss.Transport` implementation based on TCP SSL sockets
  as provided by Erlang's `:ssl` module. For the most part, users of Thousand
  Island will only ever need to deal with this module via `transport_options`
  passed to `Abyss` at startup time. A complete list of such options
  is defined via the `t::ssl.tls_server_option/0` type. This list can be somewhat
  difficult to decipher; by far the most common values to pass to this transport
  are the following:

  * `keyfile`: The path to a PEM encoded key to use for SSL
  * `certfile`: The path to a PEM encoded cert to use for SSL
  * `ip`:  The IP to listen on. Can be specified as:
    * `{1, 2, 3, 4}` for IPv4 addresses
    * `{1, 2, 3, 4, 5, 6, 7, 8}` for IPv6 addresses
    * `:loopback` for local loopback
    * `:any` for all interfaces (ie: `0.0.0.0`)
    * `{:local, "/path/to/socket"}` for a Unix domain socket. If this option is used, the `port`
      option *must* be set to `0`.

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

  @type options() :: [:ssl.tls_server_option()]
  @type listener_socket() :: :ssl.sslsocket()
  @type socket() :: :ssl.sslsocket()

  @behaviour Abyss.Transport

  @hardcoded_options [mode: :binary, active: false]

  @impl Abyss.Transport
  @spec listen(:inet.port_number(), [:ssl.tls_server_option()]) ::
          Abyss.Transport.on_listen()
  def listen(port, user_options) do
    default_options = [
      backlog: 1024,
      nodelay: true,
      send_timeout: 30_000,
      send_timeout_close: true,
      reuseaddr: true
    ]

    # We can't use Keyword functions here because :ssl accepts non-keyword style options
    resolved_options =
      Enum.uniq_by(
        @hardcoded_options ++ user_options ++ default_options,
        fn
          {key, _} when is_atom(key) -> key
          key when is_atom(key) -> key
        end
      )

    if not Enum.any?(
         [:certs_keys, :keyfile, :key, :sni_hosts, :sni_fun],
         &:proplists.is_defined(&1, resolved_options)
       ) do
      raise "transport_options must include one of keyfile, key, sni_hosts or sni_fun"
    end

    if not Enum.any?(
         [:certs_keys, :certfile, :cert, :sni_hosts, :sni_fun],
         &:proplists.is_defined(&1, resolved_options)
       ) do
      raise "transport_options must include one of certfile, cert, sni_hosts or sni_fun"
    end

    :ssl.listen(port, resolved_options)
  end

  @impl Abyss.Transport
  @spec accept(listener_socket()) :: Abyss.Transport.on_accept()
  defdelegate accept(listener_socket), to: :ssl, as: :transport_accept

  @impl Abyss.Transport
  @spec handshake(socket()) :: Abyss.Transport.on_handshake()
  def handshake(socket) do
    case :ssl.handshake(socket) do
      {:ok, socket, _protocol_extensions} -> {:ok, socket}
      other -> other
    end
  end

  @impl Abyss.Transport
  @spec upgrade(socket(), options()) :: Abyss.Transport.on_upgrade()
  def upgrade(socket, opts) do
    case :ssl.handshake(socket, opts) do
      {:ok, socket, _protocol_extensions} -> {:ok, socket}
      other -> other
    end
  end

  @impl Abyss.Transport
  @spec controlling_process(socket(), pid()) :: Abyss.Transport.on_controlling_process()
  defdelegate controlling_process(socket, pid), to: :ssl

  @impl Abyss.Transport
  @spec recv(socket(), non_neg_integer(), timeout()) :: Abyss.Transport.on_recv()
  defdelegate recv(socket, length, timeout), to: :ssl

  @impl Abyss.Transport
  @spec send(socket(), iodata()) :: Abyss.Transport.on_send()
  defdelegate send(socket, data), to: :ssl

  @impl Abyss.Transport
  @spec sendfile(
          socket(),
          filename :: String.t(),
          offset :: non_neg_integer(),
          length :: non_neg_integer()
        ) :: Abyss.Transport.on_sendfile()
  def sendfile(socket, filename, offset, length) do
    # We can't use :file.sendfile here since it works on clear sockets, not ssl
    # sockets. Build our own (much slower and not optimized for large files) version.
    case :file.open(filename, [:raw]) do
      {:ok, fd} ->
        try do
          with {:ok, data} <- :file.pread(fd, offset, length),
               :ok <- :ssl.send(socket, data) do
            {:ok, length}
          else
            :eof -> {:error, :eof}
            {:error, reason} -> {:error, reason}
          end
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
  defdelegate getopts(socket, options), to: :ssl

  @impl Abyss.Transport
  @spec setopts(socket(), Abyss.Transport.socket_set_options()) ::
          Abyss.Transport.on_setopts()
  defdelegate setopts(socket, options), to: :ssl

  @impl Abyss.Transport
  @spec shutdown(socket(), Abyss.Transport.way()) ::
          Abyss.Transport.on_shutdown()
  defdelegate shutdown(socket, way), to: :ssl

  @impl Abyss.Transport
  @spec close(socket() | listener_socket()) :: Abyss.Transport.on_close()
  defdelegate close(socket), to: :ssl

  # :ssl.sockname/1's typespec is incorrect
  @dialyzer {:no_match, sockname: 1}

  @impl Abyss.Transport
  @spec sockname(socket() | listener_socket()) :: Abyss.Transport.on_sockname()
  defdelegate sockname(socket), to: :ssl

  # :ssl.peername/1's typespec is incorrect
  @dialyzer {:no_match, peername: 1}

  @impl Abyss.Transport
  @spec peername(socket()) :: Abyss.Transport.on_peername()
  defdelegate peername(socket), to: :ssl

  @impl Abyss.Transport
  @spec peercert(socket()) :: Abyss.Transport.on_peercert()
  defdelegate peercert(socket), to: :ssl

  @impl Abyss.Transport
  @spec secure?() :: true
  def secure?, do: true

  @impl Abyss.Transport
  @spec getstat(socket()) :: Abyss.Transport.socket_stats()
  defdelegate getstat(socket), to: :ssl

  @impl Abyss.Transport
  @spec negotiated_protocol(socket()) :: Abyss.Transport.on_negotiated_protocol()
  defdelegate negotiated_protocol(socket), to: :ssl
end
