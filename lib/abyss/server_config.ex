defmodule Abyss.ServerConfig do
  @moduledoc """
  Encapsulates the configuration of a Abyss server instance

  This is used internally by `Abyss.Handler`
  """

  @typedoc "A set of configuration parameters for a Abyss server instance"
  @type t :: %__MODULE__{
          port: :inet.port_number(),
          transport_options: Abyss.transport_options(),
          handler_module: module(),
          handler_options: term(),
          genserver_options: GenServer.options(),
          supervisor_options: [Supervisor.option()],
          broadcast: boolean(),
          num_listeners: pos_integer(),
          num_connections: non_neg_integer() | :infinity,
          max_connections_retry_count: non_neg_integer(),
          max_connections_retry_wait: timeout(),
          read_timeout: timeout(),
          shutdown_timeout: timeout(),
          silent_terminate_on_error: boolean()
        }

  defstruct port: 4000,
            transport_options: [],
            handler_module: nil,
            handler_options: [],
            genserver_options: [],
            supervisor_options: [],
            broadcast: false,
            num_listeners: 100,
            num_connections: 16_384,
            max_connections_retry_count: 5,
            max_connections_retry_wait: 1000,
            read_timeout: 60_000,
            shutdown_timeout: 15_000,
            silent_terminate_on_error: false

  @spec new(Abyss.options()) :: t()
  def new(opts \\ []) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "configuration must be a keyword list"
    end

    unless Keyword.has_key?(opts, :handler_module) do
      raise ArgumentError, "No handler_module defined in server configuration"
    end

    handler_module = Keyword.get(opts, :handler_module)

    unless is_atom(handler_module) do
      raise ArgumentError, "handler_module must be a module"
    end

    broadcast = get_in(opts, [:transport_options, :broadcast])

    opts =
      if broadcast == true do
        opts |> Keyword.put(:broadcast, true)
      else
        opts
      end

    struct!(__MODULE__, opts)
  end
end
