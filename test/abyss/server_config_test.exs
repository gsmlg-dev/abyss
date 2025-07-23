defmodule Abyss.ServerConfigTest do
  use ExUnit.Case, async: true
  doctest Abyss.ServerConfig

  describe "new/1" do
    test "creates config with default values" do
      config = Abyss.ServerConfig.new(handler_module: Abyss.TestHandler, port: 1234)

      assert config.handler_module == Abyss.TestHandler
      assert config.port == 1234
      assert config.handler_options == []
      assert config.genserver_options == []
      assert config.supervisor_options == []
      assert config.transport_options == []
      assert config.num_listeners == 100
      assert config.num_connections == 16_384
      assert config.max_connections_retry_count == 5
      assert config.max_connections_retry_wait == 1000
      assert config.read_timeout == 60_000
      assert config.shutdown_timeout == 15_000
      assert config.silent_terminate_on_error == false
      assert config.broadcast == false
    end

    test "allows custom configuration values" do
      config =
        Abyss.ServerConfig.new(
          handler_module: Abyss.TestHandler,
          port: 5678,
          transport_options: [recbuf: 8192],
          num_listeners: 10,
          num_connections: 1000,
          read_timeout: 30_000,
          broadcast: true
        )

      assert config.handler_module == Abyss.TestHandler
      assert config.port == 5678
      assert config.transport_options == [recbuf: 8192]
      assert config.num_listeners == 10
      assert config.num_connections == 1000
      assert config.read_timeout == 30_000
      assert config.broadcast == true
    end

    test "accepts any handler module (no validation)" do
      config = Abyss.ServerConfig.new(handler_module: :not_a_module, port: 1234)
      assert config.handler_module == :not_a_module
    end

    test "accepts any port value" do
      config = Abyss.ServerConfig.new(handler_module: Abyss.TestHandler, port: -1)
      assert config.port == -1

      config = Abyss.ServerConfig.new(handler_module: Abyss.TestHandler, port: 99999)
      assert config.port == 99999
    end

    test "accepts any num_listeners value" do
      config =
        Abyss.ServerConfig.new(handler_module: Abyss.TestHandler, port: 1234, num_listeners: 0)

      assert config.num_listeners == 0

      config =
        Abyss.ServerConfig.new(handler_module: Abyss.TestHandler, port: 1234, num_listeners: -5)

      assert config.num_listeners == -5
    end

    test "accepts any num_connections value" do
      config =
        Abyss.ServerConfig.new(handler_module: Abyss.TestHandler, port: 1234, num_connections: -1)

      assert config.num_connections == -1

      config =
        Abyss.ServerConfig.new(
          handler_module: Abyss.TestHandler,
          port: 1234,
          num_connections: :infinity
        )

      assert config.num_connections == :infinity
    end

    test "accepts any timeout values" do
      config =
        Abyss.ServerConfig.new(handler_module: Abyss.TestHandler, port: 1234, read_timeout: -1)

      assert config.read_timeout == -1

      config =
        Abyss.ServerConfig.new(
          handler_module: Abyss.TestHandler,
          port: 1234,
          shutdown_timeout: -1000
        )

      assert config.shutdown_timeout == -1000
    end
  end

  describe "struct fields" do
    test "has correct struct definition" do
      config = Abyss.ServerConfig.new(handler_module: Abyss.TestHandler, port: 1234)

      assert %Abyss.ServerConfig{
               handler_module: Abyss.TestHandler,
               handler_options: [],
               genserver_options: [],
               supervisor_options: [],
               port: 1234,
               transport_options: [],
               broadcast: false,
               num_listeners: 100,
               num_connections: 16_384,
               max_connections_retry_count: 5,
               max_connections_retry_wait: 1000,
               read_timeout: 60_000,
               shutdown_timeout: 15_000,
               silent_terminate_on_error: false
             } = config
    end
  end
end
