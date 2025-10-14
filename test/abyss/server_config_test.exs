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
               silent_terminate_on_error: false,
               rate_limit_enabled: false,
               rate_limit_max_packets: 1000,
               rate_limit_window_ms: 1000,
               max_packet_size: 8192
             } = config
    end
  end

  describe "rate limiting configuration" do
    test "includes rate limiting fields" do
      config =
        Abyss.ServerConfig.new(
          handler_module: Abyss.TestHandler,
          port: 1234,
          rate_limit_enabled: true,
          rate_limit_max_packets: 500,
          rate_limit_window_ms: 2000
        )

      assert config.rate_limit_enabled == true
      assert config.rate_limit_max_packets == 500
      assert config.rate_limit_window_ms == 2000
    end

    test "has default rate limiting values" do
      config = Abyss.ServerConfig.new(handler_module: Abyss.TestHandler, port: 1234)

      assert config.rate_limit_enabled == false
      assert config.rate_limit_max_packets == 1000
      assert config.rate_limit_window_ms == 1000
    end
  end

  describe "packet size configuration" do
    test "includes max packet size field" do
      config =
        Abyss.ServerConfig.new(
          handler_module: Abyss.TestHandler,
          port: 1234,
          max_packet_size: 4096
        )

      assert config.max_packet_size == 4096
    end

    test "has default max packet size" do
      config = Abyss.ServerConfig.new(handler_module: Abyss.TestHandler, port: 1234)

      assert config.max_packet_size == 8192
    end
  end

  describe "validation" do
    test "raises error when handler_module is missing" do
      assert_raise ArgumentError, "No handler_module defined in server configuration", fn ->
        Abyss.ServerConfig.new(port: 1234)
      end
    end

    test "raises error when options is not a keyword list" do
      assert_raise ArgumentError, "configuration must be a keyword list", fn ->
        Abyss.ServerConfig.new([{"handler_module", Abyss.TestHandler}])
      end
    end

    test "raises error when handler_module is not an atom" do
      assert_raise ArgumentError, "handler_module must be a module", fn ->
        Abyss.ServerConfig.new(handler_module: "TestModule")
      end
    end
  end
end
