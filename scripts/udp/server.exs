# Protocol-neutral supervised service used only inside the isolated fixture.
defmodule Abyss.UDPWireHandler do
  use Abyss.Handler

  def handle_data({peer, port, payload}, state) do
    family = if tuple_size(peer) == 4, do: 4, else: 6
    encoded = if payload == <<>>, do: "-", else: Base.encode64(payload)
    IO.puts("WIRE RX#{family} #{encoded}")

    if payload == <<>> or String.starts_with?(payload, "probe:") do
      destination =
        if family == 6,
          do: %{
            family: :inet6,
            addr: peer,
            port: port,
            scope_id: Keyword.fetch!(state.server_config.handler_options, :scope_id)
          },
          else: {peer, port}

      :ok = Abyss.Transport.UDP.send(state.socket, destination, "reply:" <> payload)
    end

    {:close, state}
  end
end

defmodule Abyss.UDPWireControl do
  def address(text) do
    {:ok, address} = :inet.parse_address(String.to_charlist(text))
    address
  end

  def index(name) do
    {:ok, names} = :net.if_names()
    {index, _} = Enum.find(names, fn {_, interface} -> interface == String.to_charlist(name) end)
    index
  end

  def start(port4, port6) do
    backend =
      case System.get_env("ABYSS_UDP_BACKEND", "inet") do
        "inet" -> :inet
        "socket" -> :socket
        value -> raise ArgumentError, "unsupported fixture backend: #{inspect(value)}"
      end

    group4 = address("239.192.74.1")
    group4b = address("239.192.74.2")
    group6 = address("ff02::114")
    group6b = address("ff02::115")

    {:ok, server4} =
      Abyss.start_link(
        handler_module: Abyss.UDPWireHandler,
        port: port4,
        broadcast: true,
        num_connections: 16,
        transport_module: Abyss.Transport.UDP.Multicast,
        transport_options: [
          inet_backend: backend,
          reuseaddr: true,
          multicast_if: {192, 0, 2, 10},
          add_membership: {group4, {192, 0, 2, 10}},
          add_membership: {group4b, {192, 0, 2, 10}},
          multicast_ttl: 1,
          multicast_loop: true
        ]
      )

    {:ok, server6} =
      Abyss.start_link(
        handler_module: Abyss.UDPWireHandler,
        port: port6,
        num_connections: 16,
        handler_options: [scope_id: index("eth0")],
        transport_module: Abyss.Transport.UDP.Multicast,
        transport_options: [
          {:inet_backend, backend},
          :inet6,
          {:ipv6_v6only, true},
          {:reuseaddr, true},
          {:multicast_if, index("eth0")},
          {:add_membership, {group6, index("eth0")}},
          {:add_membership, {group6b, index("eth0")}},
          {:multicast_ttl, 1},
          {:multicast_loop, true}
        ]
      )

    %{4 => server4, 6 => server6}
  end

  def socket(server) do
    [listener] = server |> Abyss.Server.listener_pool_pid() |> Abyss.ListenerPool.listener_pids()
    {socket, _} = Abyss.Listener.socket_info(listener)
    socket
  end

  def execute(["SCOPE_UNSUPPORTED"], servers) do
    destination = %{family: :inet6, addr: {0, 0, 0, 0, 0, 0, 0, 1}, port: 49000, scope_id: 1}

    case Abyss.Transport.UDP.send(socket(servers[6]), destination, "capability-probe") do
      {:error, {:unsupported_capability, :scoped_sockaddr_send, :socket}} -> :ok
      result -> {:error, {:unexpected_scope_capability_result, result}}
    end
  end

  def execute(["SEND", family, host, port, interface, encoded], servers) do
    family = String.to_integer(family)

    destination =
      if family == 6,
        do: %{
          family: :inet6,
          addr: address(host),
          port: String.to_integer(port),
          scope_id: index(interface)
        },
        else: {address(host), String.to_integer(port)}

    Abyss.Transport.UDP.send(
      socket(servers[family]),
      destination,
      if(encoded == "-", do: <<>>, else: Base.decode64!(encoded))
    )
  end

  def execute([operation, family, group, interface], servers)
      when operation in ["JOIN", "LEAVE"] do
    family = String.to_integer(family)
    membership = {address(group), if(family == 6, do: index(interface), else: address(interface))}

    if operation == "JOIN",
      do: Abyss.join(servers[family], membership),
      else: Abyss.leave(servers[family], membership)
  end

  def execute(["OPTIONS", family, ttl, loop], servers) do
    Abyss.Transport.UDP.setopts(socket(servers[String.to_integer(family)]),
      multicast_ttl: String.to_integer(ttl),
      multicast_loop: loop == "true"
    )
  end

  def execute(["INTERFACE", family, interface], servers) do
    family = String.to_integer(family)

    Abyss.Transport.UDP.setopts(socket(servers[family]),
      multicast_if: if(family == 6, do: index(interface), else: address(interface))
    )
  end

  def execute(["BARRIER"], _servers), do: :ok

  def execute(["STOP"], servers) do
    for {_family, server} <- servers, do: :ok = Abyss.stop(server, 1000)
    :ok
  end

  def run(servers) do
    case IO.gets("") do
      :eof ->
        :ok

      line ->
        [id | command] = String.split(String.trim(line))
        result = execute(command, servers)

        case result do
          :ok ->
            IO.puts("WIRE OK #{id}")

          {:ok, _} ->
            IO.puts("WIRE OK #{id}")

          error ->
            IO.puts("WIRE ERROR #{id} #{inspect(error)}")
            raise "wire operation failed"
        end

        if command != ["STOP"], do: run(servers)
    end
  end
end

[port4, port6] = System.argv()
servers = Abyss.UDPWireControl.start(String.to_integer(port4), String.to_integer(port6))

IO.puts(
  "WIRE RUNTIME " <>
    inspect(%{
      otp: List.to_string(:erlang.system_info(:otp_release)),
      erts: List.to_string(:erlang.system_info(:version)),
      elixir: System.version(),
      backend: System.get_env("ABYSS_UDP_BACKEND", "inet")
    })
)

IO.puts("WIRE READY")
Abyss.UDPWireControl.run(servers)
