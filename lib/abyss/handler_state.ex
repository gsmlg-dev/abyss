defmodule Abyss.HandlerState do
  defstruct listener: nil,
            remote: nil,
            server_config: %Abyss.ServerConfig{},
            handler_options: [],
            connection_span: nil
end
