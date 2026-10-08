defmodule Abyss.TableOwnerScopeTest do
  use ExUnit.Case, async: false

  test "abrupt server death removes endpoint metrics, socket registrations and desired memberships" do
    server =
      spawn(fn ->
        receive do
          :finish -> :ok
        end
      end)

    socket = make_ref()
    Abyss.Telemetry.register_scope(server, ScopeHandler)
    Abyss.Telemetry.register_socket(server, socket)
    Abyss.Telemetry.track_connection_accepted(server)
    Abyss.TableOwner.ensure_table(:abyss_udp_memberships, [:named_table, :public, :set])
    :ets.insert(:abyss_udp_memberships, {{server, 1}, [{{239, 1, 2, 3}, {127, 0, 0, 1}}]})
    state = :sys.get_state(Abyss.TableOwner)
    assert map_size(state.scopes) >= 1
    Process.exit(server, :kill)
    wait_for_cleanup(server, socket, 100)
    assert :ets.lookup(:abyss_udp_memberships, {server, 1}) == []
    refute Map.has_key?(:sys.get_state(Abyss.TableOwner).scopes, server)
  end

  defp wait_for_cleanup(_server, _socket, 0), do: flunk("endpoint cleanup did not complete")

  defp wait_for_cleanup(server, socket, retries) do
    :sys.get_state(Abyss.TableOwner)

    if Abyss.Telemetry.socket_scope(socket) != :unscoped do
      wait_for_cleanup(server, socket, retries - 1)
    else
      assert Abyss.Telemetry.get_metrics(server).connections_active == 0
    end
  end
end
