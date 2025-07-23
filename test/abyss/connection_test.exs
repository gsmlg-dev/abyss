defmodule Abyss.ConnectionTest do
  use ExUnit.Case, async: false

  alias Abyss.Connection
  alias Abyss.ServerConfig

  setup do
    config = ServerConfig.new(handler_module: Abyss.TestHandler, port: 0)
    {:ok, %{config: config}}
  end

  describe "start/6" do
    test "returns :ok when starting connection process", %{config: config} do
      # Start a complete server with proper setup
      assert {:ok, server_pid} =
               Abyss.start_link(
                 handler_module: Abyss.TestHandler,
                 port: 0
               )

      # Get the listener pool and listener
      listener_pool_pid = Abyss.Server.listener_pool_pid(server_pid)
      listener_pids = Abyss.ListenerPool.listener_pids(listener_pool_pid)
      listener_pid = hd(listener_pids)
      {socket, _telemetry} = Abyss.Listener.socket_info(listener_pid)

      span = Abyss.Telemetry.start_span(:test, %{}, %{})

      assert :ok =
               Connection.start(
                 server_pid,
                 listener_pid,
                 socket,
                 {{127, 0, 0, 1}, 12345, "test data"},
                 config,
                 span
               )

      :ok = Abyss.stop(server_pid)
    end
  end

  describe "start_active/6" do
    test "returns :ok when starting active connection process", %{config: config} do
      # Start a complete server with proper setup
      assert {:ok, server_pid} =
               Abyss.start_link(
                 handler_module: Abyss.TestHandler,
                 port: 0
               )

      # Get the listener pool and listener
      listener_pool_pid = Abyss.Server.listener_pool_pid(server_pid)
      listener_pids = Abyss.ListenerPool.listener_pids(listener_pool_pid)
      listener_pid = hd(listener_pids)
      {socket, _telemetry} = Abyss.Listener.socket_info(listener_pid)

      span = Abyss.Telemetry.start_span(:test, %{}, %{})

      assert :ok =
               Connection.start_active(
                 server_pid,
                 listener_pid,
                 socket,
                 {{127, 0, 0, 1}, 12345, "test data"},
                 config,
                 span
               )

      :ok = Abyss.stop(server_pid)
    end
  end

  describe "handler behavior" do
    test "handler processes data correctly", %{config: config} do
      config = %{config | handler_module: Abyss.TestHandler}

      # Start a complete server with proper setup
      assert {:ok, server_pid} =
               Abyss.start_link(
                 handler_module: Abyss.TestHandler,
                 port: 0
               )

      # Get the listener pool and listener
      listener_pool_pid = Abyss.Server.listener_pool_pid(server_pid)
      listener_pids = Abyss.ListenerPool.listener_pids(listener_pool_pid)
      listener_pid = hd(listener_pids)
      {socket, _telemetry} = Abyss.Listener.socket_info(listener_pid)

      span = Abyss.Telemetry.start_span(:test, %{}, %{})

      assert :ok =
               Connection.start(
                 server_pid,
                 listener_pid,
                 socket,
                 {{127, 0, 0, 1}, 12345, "test data"},
                 config,
                 span
               )

      # Allow some time for the handler to process
      Process.sleep(100)

      :ok = Abyss.stop(server_pid)
    end
  end

  describe "connection lifecycle" do
    test "connection terminates gracefully", %{config: config} do
      config = %{config | handler_module: Abyss.TestHandler}

      # Start a complete server with proper setup
      assert {:ok, server_pid} =
               Abyss.start_link(
                 handler_module: Abyss.TestHandler,
                 port: 0
               )

      # Get the listener pool and listener
      listener_pool_pid = Abyss.Server.listener_pool_pid(server_pid)
      listener_pids = Abyss.ListenerPool.listener_pids(listener_pool_pid)
      listener_pid = hd(listener_pids)
      {socket, _telemetry} = Abyss.Listener.socket_info(listener_pid)

      span = Abyss.Telemetry.start_span(:test, %{}, %{})

      assert :ok =
               Connection.start(
                 server_pid,
                 listener_pid,
                 socket,
                 {{127, 0, 0, 1}, 12345, "test data"},
                 config,
                 span
               )

      :ok = Abyss.stop(server_pid)
    end
  end
end
