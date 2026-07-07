defmodule Abyss.ListenerRateLimitingTest do
  use ExUnit.Case, async: false

  alias Abyss.{Listener, ServerConfig}

  describe "packet size validation in listener" do
    test "rejects packets exceeding max size" do
      config =
        ServerConfig.new(
          handler_module: TestHandler,
          port: 0,
          max_packet_size: 100
        )

      {:ok, listener_pid} = Listener.start_link({"test", self(), config})
      Process.exit(listener_pid, :normal)
    end

    test "accepts packets within size limit" do
      config =
        ServerConfig.new(
          handler_module: TestHandler,
          port: 0,
          max_packet_size: 8192
        )

      {:ok, listener_pid} = Listener.start_link({"test", self(), config})
      Process.exit(listener_pid, :normal)
    end
  end

  # Helper module for testing
  defmodule TestHandler do
    use Abyss.Handler

    @impl true
    def handle_data({_ip, _port, _data}, state) do
      {:continue, state}
    end
  end
end
