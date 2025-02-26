defmodule TelemetryHelpers do
  @moduledoc false

  @events [
    [:abyss, :listener, :start],
    [:abyss, :listener, :stop],
    [:abyss, :acceptor, :start],
    [:abyss, :acceptor, :stop],
    [:abyss, :acceptor, :spawn_error],
    [:abyss, :acceptor, :econnaborted],
    [:abyss, :connection, :start],
    [:abyss, :connection, :stop],
    [:abyss, :connection, :ready],
    [:abyss, :connection, :async_recv],
    [:abyss, :connection, :recv],
    [:abyss, :connection, :recv_error],
    [:abyss, :connection, :send],
    [:abyss, :connection, :send_error],
    [:abyss, :connection, :sendfile],
    [:abyss, :connection, :sendfile_error],
    [:abyss, :connection, :socket_shutdown]
  ]

  def attach_all_events(handler) do
    ref = make_ref()
    _ = :telemetry.attach_many(ref, @events, &__MODULE__.handle_event/4, {self(), handler})
    fn -> :telemetry.detach(ref) end
  end

  def handle_event(event, measurements, %{handler: handler} = metadata, {pid, handler}),
    do: send(pid, {:telemetry, event, measurements, metadata})

  def handle_event(_event, _measurements, _metadata, {_pid, _handler}), do: :ok
end
