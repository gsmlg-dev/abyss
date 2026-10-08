defmodule Abyss.ServerConfig do
  @moduledoc """
  Encapsulates the configuration of a Abyss server instance

  This is used internally by `Abyss.Handler`
  """

  require Logger

  @typedoc "A set of configuration parameters for a Abyss server instance"
  @type t :: %__MODULE__{
          port: :inet.port_number(),
          transport_module: module(),
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
          udp_buffer_size: pos_integer(),
          dynamic_listeners: boolean(),
          min_listeners: pos_integer(),
          max_listeners: pos_integer(),
          listener_scale_threshold: float(),
          silent_terminate_on_error: boolean(),
          max_packet_size: pos_integer(),
          connection_telemetry_sample_rate: float(),
          handler_memory_check_interval: pos_integer(),
          handler_memory_warning_threshold: pos_integer(),
          handler_memory_hard_limit: pos_integer(),
          datagram_dispatcher: nil | module() | {module(), keyword()},
          dispatcher_options: keyword(),
          dispatcher_max_queue: pos_integer(),
          dispatcher_max_queue_bytes: pos_integer(),
          admission_start_timeout: pos_integer()
        }

  @connections_per_listener 100
  @processing_time_baseline_ms 100
  @min_processing_factor 0.5

  defstruct port: 4000,
            transport_module: Abyss.Transport.UDP,
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
            udp_buffer_size: 64 * 1024,
            dynamic_listeners: false,
            min_listeners: 10,
            max_listeners: 1000,
            listener_scale_threshold: 0.8,
            silent_terminate_on_error: false,
            max_packet_size: 8192,
            connection_telemetry_sample_rate: 0.05,
            handler_memory_check_interval: 10_000,
            handler_memory_warning_threshold: 100,
            handler_memory_hard_limit: 150,
            datagram_dispatcher: nil,
            dispatcher_options: [],
            dispatcher_max_queue: 128,
            dispatcher_max_queue_bytes: 1_048_576,
            admission_start_timeout: 1000

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

    # num_acceptors is deprecated but documented; map it to num_listeners
    # rather than crashing in struct!/2 (it is not a struct field).
    {num_acceptors, opts} = Keyword.pop(opts, :num_acceptors)

    opts =
      if num_acceptors do
        Logger.warning("Option :num_acceptors is deprecated. Use :num_listeners instead.")
        Keyword.put_new(opts, :num_listeners, num_acceptors)
      else
        opts
      end

    # Determine broadcast mode from transport module
    transport_module = Keyword.get(opts, :transport_module, Abyss.Transport.UDP)
    is_broadcast = transport_module == Abyss.Transport.UDP.Broadcast

    opts =
      if is_broadcast do
        Keyword.put(opts, :broadcast, true)
      else
        opts
      end

    config = struct!(__MODULE__, opts)

    # Validate numeric ranges for new configuration options
    validate_config!(config)

    config
  end

  # Private validation function
  defp validate_config!(config) do
    _ = validate_limits!(config)
    _ = validate_timeouts!(config)
    validate_socket_options!(config)
    validate_scaling!(config)
    validate_resources!(config)
    validate_dispatcher!(config)
    :ok
  end

  defp validate_limits!(config) do
    for {name, value} <- [
          num_listeners: config.num_listeners,
          num_connections: config.num_connections,
          max_packet_size: config.max_packet_size,
          udp_buffer_size: config.udp_buffer_size,
          admission_start_timeout: config.admission_start_timeout
        ] do
      unless is_integer(value) and value > 0,
        do: raise(ArgumentError, "#{name} must be a positive integer")
    end

    unless is_integer(config.port) and config.port in 0..65_535,
      do: raise(ArgumentError, "port must be between 0 and 65535")
  end

  defp validate_timeouts!(config) do
    for {name, value} <- [
          read_timeout: config.read_timeout,
          shutdown_timeout: config.shutdown_timeout
        ] do
      unless value == :infinity or (is_integer(value) and value >= 0),
        do: raise(ArgumentError, "#{name} must be a non-negative timeout or :infinity")
    end
  end

  defp validate_socket_options!(config) do
    for key <- [:broadcast, :dynamic_listeners, :silent_terminate_on_error] do
      unless is_boolean(Map.fetch!(config, key)),
        do: raise(ArgumentError, "#{key} must be boolean")
    end

    unless is_list(config.transport_options),
      do: raise(ArgumentError, "transport_options must be a list")

    for option <- config.transport_options do
      case option do
        {:active, value} when value not in [false, :once] ->
          raise ArgumentError, "host owns receive activation; active must be false or :once"

        :list ->
          raise ArgumentError, "host requires binary datagrams"

        {:mode, :list} ->
          raise ArgumentError, "host requires binary datagrams"

        _ ->
          :ok
      end
    end

    validate_dynamic_endpoint!(config)
  end

  defp validate_dynamic_endpoint!(config) do
    membership? = Enum.any?(config.transport_options, &match?({:add_membership, _}, &1))

    if config.dynamic_listeners and
         (config.broadcast or config.port == 0 or membership? or
            config.transport_module == Abyss.Transport.UDP.Multicast),
       do:
         raise(
           ArgumentError,
           "dynamic receive-socket scaling is incompatible with ephemeral, broadcast or multicast endpoints"
         )
  end

  defp validate_scaling!(config) do
    # Validate listener scaling configuration
    unless is_integer(config.min_listeners) and is_integer(config.max_listeners) and
             config.min_listeners > 0 and config.min_listeners <= config.max_listeners do
      raise ArgumentError,
            "min_listeners must be positive and <= max_listeners (got min: #{config.min_listeners}, max: #{config.max_listeners})"
    end

    unless is_number(config.listener_scale_threshold) and config.listener_scale_threshold > 0.0 and
             config.listener_scale_threshold <= 1.0 do
      raise ArgumentError,
            "listener_scale_threshold must be between 0.0 and 1.0 (got #{config.listener_scale_threshold})"
    end
  end

  defp validate_resources!(config) do
    # Validate telemetry sampling rate
    unless is_number(config.connection_telemetry_sample_rate) and
             config.connection_telemetry_sample_rate >= 0.0 and
             config.connection_telemetry_sample_rate <= 1.0 do
      raise ArgumentError,
            "connection_telemetry_sample_rate must be between 0.0 and 1.0 (got #{config.connection_telemetry_sample_rate})"
    end

    validate_memory!(config)
  end

  defp validate_memory!(config) do
    # Validate memory thresholds
    unless is_integer(config.handler_memory_check_interval) and
             config.handler_memory_check_interval > 0 do
      raise ArgumentError,
            "handler_memory_check_interval must be positive (got #{config.handler_memory_check_interval})"
    end

    unless is_number(config.handler_memory_warning_threshold) and
             is_number(config.handler_memory_hard_limit) and
             config.handler_memory_warning_threshold > 0 and
             config.handler_memory_warning_threshold < config.handler_memory_hard_limit do
      raise ArgumentError,
            "handler_memory_warning_threshold must be positive and < handler_memory_hard_limit (got warning: #{config.handler_memory_warning_threshold}, hard limit: #{config.handler_memory_hard_limit})"
    end

    :ok
  end

  defp validate_dispatcher!(%__MODULE__{datagram_dispatcher: nil}), do: :ok

  defp validate_dispatcher!(%__MODULE__{broadcast: true, datagram_dispatcher: dispatcher})
       when not is_nil(dispatcher),
       do: raise(ArgumentError, "datagram_dispatcher is only supported for unicast listeners")

  defp validate_dispatcher!(%__MODULE__{} = config) do
    dispatcher_module =
      case config.datagram_dispatcher do
        module when is_atom(module) -> module
        {module, opts} when is_atom(module) and is_list(opts) -> module
        _ -> nil
      end

    loaded? = not is_nil(dispatcher_module) and Code.ensure_loaded?(dispatcher_module)

    unless loaded? and function_exported?(dispatcher_module, :init, 2) and
             function_exported?(dispatcher_module, :handle_datagram, 4) do
      raise ArgumentError,
            "datagram_dispatcher must be a module exporting init/2 and handle_datagram/4"
    end

    validate_dispatcher_limits!(config)
  end

  defp validate_dispatcher_limits!(config) do
    unless Keyword.keyword?(config.dispatcher_options) do
      raise ArgumentError, "dispatcher_options must be a keyword list"
    end

    unless is_integer(config.dispatcher_max_queue) and config.dispatcher_max_queue > 0 do
      raise ArgumentError, "dispatcher_max_queue must be positive"
    end

    unless is_integer(config.dispatcher_max_queue_bytes) and config.dispatcher_max_queue_bytes > 0 do
      raise ArgumentError, "dispatcher_max_queue_bytes must be positive"
    end
  end

  @doc """
  Calculate optimal number of listeners based on current load and processing characteristics

  Uses a more granular scaling approach:
  - 1 listener per 100 connections (instead of 1000)
  - Adjusts for processing time with a lower bound of 0.5x
  - Ensures minimum of 1 listener

  ## Examples

      iex> Abyss.ServerConfig.calculate_optimal_listeners(50, 100.0)
      1

      iex> Abyss.ServerConfig.calculate_optimal_listeners(500, 100.0)
      5

      iex> Abyss.ServerConfig.calculate_optimal_listeners(500, 200.0)
      10
  """
  @spec calculate_optimal_listeners(pos_integer(), float()) :: pos_integer()
  def calculate_optimal_listeners(current_connections, avg_processing_time_ms) do
    # Start with at least 1 listener per @connections_per_listener connections
    base_listeners = max(div(current_connections, @connections_per_listener), 1)

    # Adjust for processing time (slower processing = more listeners needed)
    # Normalize to @processing_time_baseline_ms baseline
    processing_factor =
      max(avg_processing_time_ms / @processing_time_baseline_ms, @min_processing_factor)

    optimal = round(base_listeners * processing_factor)

    # Ensure reasonable bounds
    max(optimal, 1)
  end
end
