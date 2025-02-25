defmodule Abyss.Transport do
  @moduledoc """
  This module describes the behaviour required for Abyss to interact
  with low-level sockets. It is largely internal to Abyss, however users
  are free to implement their own versions of this behaviour backed by whatever
  underlying transport they choose. Such a module can be used in Abyss
  by passing its name as the `transport_module` option when starting up a server,
  as described in `Abyss`.
  """

  @typedoc "A listener socket used to wait for connections"
  @type listener_socket() :: :inet.socket()

  @typedoc "A listener socket options"
  @type listen_options() ::
          [:inet.inet_backend() | :gen_tcp.listen_option()] | [:gen_udp.open_option()]

  @typedoc "A socket representing a client connection"
  @type socket() :: :inet.socket()

  @typedoc "Information about an endpoint, either remote ('peer') or local"
  @type socket_info() ::
          {:inet.ip_address(), :inet.port_number()} | :inet.returned_non_ip_address()

  @typedoc "A socket address"
  @type address ::
          :inet.ip_address()
          | :inet.local_address()
          | {:local, binary()}
          | :unspec
          | {:undefined, any()}
  @typedoc "Connection statistics for a given socket"
  @type socket_stats() :: {:ok, [{:inet.stat_option(), integer()}]} | {:error, :inet.posix()}

  @typedoc "Options which can be set on a socket via setopts/2 (or returned from getopts/1)"
  @type socket_get_options() :: [:inet.socket_getopt()]

  @typedoc "Options which can be set on a socket via setopts/2 (or returned from getopts/1)"
  @type socket_set_options() :: [:inet.socket_setopt()]

  @typedoc "The return value from a listen/2 call"
  @type on_listen() ::
          {:ok, listener_socket()} | {:error, :system_limit} | {:error, :inet.posix()}

  @typedoc "The return value from a controlling_process/2 call"
  @type on_controlling_process() :: :ok | {:error, :closed | :not_owner | :badarg | :inet.posix()}

  @typedoc "The return value from a upgrade/2 call"
  @type on_upgrade() :: {:ok, socket()} | {:error, term()}

  @typedoc "The return value from a close/1 call"
  @type on_close() :: :ok | {:error, any()}

  @typedoc "The return value from a recv/3 call"
  @type on_recv() :: {:ok, binary()} | {:error, :closed | :timeout | :inet.posix()}

  @typedoc "The return value from a send/2 call"
  @type on_send() :: :ok | {:error, :closed | {:timeout, rest_data :: binary()} | :inet.posix()}

  @typedoc "The return value from a sendfile/4 call"
  @type on_sendfile() ::
          {:ok, non_neg_integer()}
          | {:error, :inet.posix() | :closed | :badarg | :not_owner | :eof}

  @typedoc "The return value from a getopts/2 call"
  @type on_getopts() :: {:ok, [:inet.socket_optval()]} | {:error, :inet.posix()}

  @typedoc "The return value from a setopts/2 call"
  @type on_setopts() :: :ok | {:error, :inet.posix()}

  @typedoc "The return value from a sockname/1 call"
  @type on_sockname() :: {:ok, socket_info()} | {:error, :inet.posix()}

  @typedoc "The return value from a peername/1 call"
  @type on_peername() :: {:ok, socket_info()} | {:error, :inet.posix()}

  @typedoc "The return value from a negotiated_protocol/1 call"
  @type on_negotiated_protocol() ::
          {:ok, binary()} | {:error, :protocol_not_negotiated | :closed}

  @doc """
  Create and return a listener socket bound to the given port and configured per
  the provided options.
  """
  @callback listen(:inet.port_number(), listen_options()) ::
              {:ok, listener_socket()} | {:error, any()}

  @doc """
  Transfers ownership of the given socket to the given process. This will always
  be called by the process which currently owns the socket.
  """
  @callback controlling_process(socket(), pid()) :: on_controlling_process()

  @doc """
  Returns available bytes on the given socket. Up to `num_bytes` bytes will be
  returned (0 can be passed in to get the next 'available' bytes, typically the
  next packet). If insufficient bytes are available, the function can wait `timeout`
  milliseconds for data to arrive.
  """
  @callback recv(socket(), num_bytes :: non_neg_integer(), timeout :: timeout()) :: on_recv()

  @doc """
  Sends the given data (specified as a binary or an IO list) on the given socket.
  """
  @callback send(socket(), data :: iodata()) :: on_send()

  @doc """
  Sends the contents of the given file based on the provided offset & length
  """
  @callback sendfile(
              socket(),
              filename :: String.t(),
              offset :: non_neg_integer(),
              length :: non_neg_integer()
            ) :: on_sendfile()

  @doc """
  Gets the given options on the socket.
  """
  @callback getopts(socket(), socket_get_options()) :: on_getopts()

  @doc """
  Sets the given options on the socket. Should disallow setting of options which
  are not compatible with Abyss
  """
  @callback setopts(socket(), socket_set_options()) :: on_setopts()

  @doc """
  Closes the given socket.
  """
  @callback close(socket() | listener_socket()) :: on_close()

  @doc """
  Returns information in the form of `t:socket_info()` about the local end of the socket.
  """
  @callback sockname(socket() | listener_socket()) :: on_sockname()

  @doc """
  Returns information in the form of `t:socket_info()` about the remote end of the socket.
  """
  @callback peername(socket()) :: on_peername()

  @doc """
  Returns stats about the connection on the socket.
  """
  @callback getstat(socket()) :: socket_stats()

  @doc """
  Returns the protocol negotiated as part of handshaking. Most typically this is via TLS'
  ALPN or NPN extensions. If the underlying transport does not support protocol negotiation
  (or if one was not negotiated), `{:error, :protocol_not_negotiated}` is returned
  """
  @callback negotiated_protocol(socket()) :: on_negotiated_protocol()
end
