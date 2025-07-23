defmodule Abyss.TestHandler do
  @moduledoc """
  Test handler module for testing Abyss.Handler behaviour
  """
  use Abyss.Handler

  @impl true
  def handle_data({ip, port, data}, state) do
    send(self(), {:packet_received, data, {ip, port}})
    {:continue, state}
  end
end

defmodule Abyss.TestEchoHandler do
  @moduledoc """
  Test echo handler for integration testing
  """
  use Abyss.Handler

  @impl true
  def handle_data({ip, port, data}, state) do
    Abyss.Transport.UDP.send(state.socket, ip, port, data)
    {:continue, state}
  end
end
