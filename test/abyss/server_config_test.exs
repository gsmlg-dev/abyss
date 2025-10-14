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
      assert config.udp_buffer_size == 64 * 1024
      assert config.dynamic_listeners == false
      assert config.min_listeners == 10
      assert config.max_listeners == 1000
      assert config.listener_scale_threshold == 0.8
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

    test "accepts UDP buffer size configuration" do
      config =
        Abyss.ServerConfig.new(
          handler_module: Abyss.TestHandler,
          port: 1234,
          udp_buffer_size: 128 * 1024
        )

      assert config.udp_buffer_size == 128 * 1024
    end

    test "accepts dynamic listener configuration" do
      config =
        Abyss.ServerConfig.new(
          handler_module: Abyss.TestHandler,
          port: 1234,
          dynamic_listeners: true,
          min_listeners: 5,
          max_listeners: 500,
          listener_scale_threshold: 0.7
        )

      assert config.dynamic_listeners == true
      assert config.min_listeners == 5
      assert config.max_listeners == 500
      assert config.listener_scale_threshold == 0.7
    end
  end

  describe "calculate_optimal_listeners/2" do
    test "calculates optimal listeners based on connection count" do
      # Basic calculation: connections / 1000
      assert Abyss.ServerConfig.calculate_optimal_listeners(0, 100.0) == 1
      assert Abyss.ServerConfig.calculate_optimal_listeners(500, 100.0) == 1
      assert Abyss.ServerConfig.calculate_optimal_listeners(1000, 100.0) == 1
      assert Abyss.ServerConfig.calculate_optimal_listeners(2000, 100.0) == 2
      assert Abyss.ServerConfig.calculate_optimal_listeners(5000, 100.0) == 5
      assert Abyss.ServerConfig.calculate_optimal_listeners(10000, 100.0) == 10
    end

    test "adjusts for processing time" do
      # Faster processing should require fewer listeners
      # 2000/1000 = 2, max(50.0/100, 1) = 1, so 2 * 1 = 2, round(2) = 2
      assert Abyss.ServerConfig.calculate_optimal_listeners(2000, 50.0) == 2
      # 2000/1000 = 2, max(25.0/100, 1) = 1, so 2 * 1 = 2, round(2) = 2
      assert Abyss.ServerConfig.calculate_optimal_listeners(2000, 25.0) == 2

      # Slower processing should require more listeners
      assert Abyss.ServerConfig.calculate_optimal_listeners(1000, 200.0) == 2  # 1 * 2 = 2
      assert Abyss.ServerConfig.calculate_optimal_listeners(1000, 500.0) == 5  # 1 * 5 = 5
      assert Abyss.ServerConfig.calculate_optimal_listeners(1000, 1000.0) == 10 # 1 * 10 = 10
    end

    test "always returns at least 1 listener" do
      assert Abyss.ServerConfig.calculate_optimal_listeners(0, 100.0) == 1
      assert Abyss.ServerConfig.calculate_optimal_listeners(100, 10.0) == 1  # 0.1 -> 1
      assert Abyss.ServerConfig.calculate_optimal_listeners(1, 1.0) == 1    # 0.001 -> 1
    end

    test "handles edge cases" do
      # Zero processing time (very fast)
      assert Abyss.ServerConfig.calculate_optimal_listeners(1000, 0.1) == 1

      # Very high processing time
      # 100/1000 = 0, max(10000.0/100, 1) = 100, so 0 * 100 = 0, round(0) = 0, max(0, 1) = 1
      assert Abyss.ServerConfig.calculate_optimal_listeners(100, 10000.0) == 1

      # Large connection count
      result = Abyss.ServerConfig.calculate_optimal_listeners(100000, 100.0)
      assert result == 100  # 100000/1000 = 100

      # Combined high connections and slow processing
      result = Abyss.ServerConfig.calculate_optimal_listeners(10000, 500.0)
      assert result == 50   # 10000/1000 = 10, 10 * 5 = 50, round(50) = 50
    end

    test "handles floating point processing times" do
      assert Abyss.ServerConfig.calculate_optimal_listeners(1000, 123.45) == 1  # 1 * 1.2345 = 1.2345 -> round(1.2345) = 1
      assert Abyss.ServerConfig.calculate_optimal_listeners(2500, 87.3) == 2   # 2 * 0.873 = 1.746 -> round(1.746) = 2
      assert Abyss.ServerConfig.calculate_optimal_listeners(1500, 233.7) == 2 # 1 * 2.337 = 2.337 -> round(2.337) = 2
    end

    test "verifies processing factor calculation" do
      # Test the processing factor: max(avg_processing_time / 100, 1)

      # Below 100ms baseline
      assert Abyss.ServerConfig.calculate_optimal_listeners(2000, 50.0) == 2   # factor = max(0.5, 1) = 1, 2*1 = 2 -> round(2) = 2
      assert Abyss.ServerConfig.calculate_optimal_listeners(2000, 99.9) == 2   # factor = max(0.999, 1) = 1, 2*1 = 2 -> round(2) = 2

      # At 100ms baseline
      assert Abyss.ServerConfig.calculate_optimal_listeners(2000, 100.0) == 2  # factor = max(1, 1) = 1, 2*1 = 2 -> round(2) = 2

      # Above 100ms baseline
      assert Abyss.ServerConfig.calculate_optimal_listeners(2000, 150.0) == 3  # factor = max(1.5, 1) = 1.5, 2*1.5 = 3 -> round(3) = 3
      assert Abyss.ServerConfig.calculate_optimal_listeners(2000, 200.0) == 4  # factor = max(2, 1) = 2, 2*2 = 4 -> round(4) = 4
    end
  end

  describe "new configuration options" do
    test "udp_buffer_size default and custom values" do
      default_config = Abyss.ServerConfig.new(handler_module: Abyss.TestHandler, port: 1234)
      assert default_config.udp_buffer_size == 64 * 1024

      custom_config = Abyss.ServerConfig.new(
        handler_module: Abyss.TestHandler,
        port: 1234,
        udp_buffer_size: 32 * 1024
      )
      assert custom_config.udp_buffer_size == 32 * 1024
    end

    test "dynamic listener configuration defaults" do
      config = Abyss.ServerConfig.new(handler_module: Abyss.TestHandler, port: 1234)

      assert config.dynamic_listeners == false
      assert config.min_listeners == 10
      assert config.max_listeners == 1000
      assert config.listener_scale_threshold == 0.8
    end

    test "custom dynamic listener configuration" do
      config = Abyss.ServerConfig.new(
        handler_module: Abyss.TestHandler,
        port: 1234,
        dynamic_listeners: true,
        min_listeners: 20,
        max_listeners: 200,
        listener_scale_threshold: 0.75
      )

      assert config.dynamic_listeners == true
      assert config.min_listeners == 20
      assert config.max_listeners == 200
      assert config.listener_scale_threshold == 0.75
    end

    test "invalid configuration values are accepted" do
      # ServerConfig accepts any values (no validation)
      config = Abyss.ServerConfig.new(
        handler_module: Abyss.TestHandler,
        port: 1234,
        udp_buffer_size: -1000,  # Invalid but accepted
        min_listeners: 0,         # Invalid but accepted
        max_listeners: -1,        # Invalid but accepted
        listener_scale_threshold: 2.0  # Invalid but accepted
      )

      assert config.udp_buffer_size == -1000
      assert config.min_listeners == 0
      assert config.max_listeners == -1
      assert config.listener_scale_threshold == 2.0
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
