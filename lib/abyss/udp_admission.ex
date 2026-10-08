defmodule Abyss.UDPAdmission do
  @moduledoc false
  @table :abyss_udp_admission

  def reserve(server, owner, limit),
    do: Abyss.TableOwner.admission({:reserve, server, owner, limit})

  def admitted(token, pid), do: Abyss.TableOwner.admission({:admitted, token, pid})
  def release(token), do: Abyss.TableOwner.admission({:release, token})
  def release_owner(owner), do: Abyss.TableOwner.admission({:release_owner, owner})
  def release_server(server), do: Abyss.TableOwner.admission({:release_server, server})

  def transition({:reserve, server, owner, limit}) do
    ensure_table()
    :ets.insert_new(@table, {{:count, server}, 0})
    token = make_ref()
    :ets.insert(@table, {token, server, owner, nil})
    count = :ets.update_counter(@table, {:count, server}, {2, 1})

    if count <= limit and Process.alive?(owner) and Process.alive?(server) do
      {:ok, token}
    else
      release(token)
      {:error, :handler_limit}
    end
  end

  def transition({:admitted, token, pid}) do
    case :ets.lookup(@table, token) do
      [{^token, server, owner, nil}] ->
        :ets.insert(@table, {token, server, owner, pid})
        Abyss.Telemetry.track_connection_accepted(server)
        :ok

      [] ->
        {:error, :stale_owner}
    end
  end

  def transition({:release, token}) do
    case :ets.take(@table, token) do
      [{^token, server, _owner, pid}] ->
        _ = :ets.update_counter(@table, {:count, server}, {2, -1})
        if is_pid(pid), do: Abyss.Telemetry.track_connection_closed(server)
        :ok

      [] ->
        :ok
    end
  end

  def transition({:release_owner, owner}) do
    ensure_table()

    for {token, _server, ^owner, pid} <- :ets.match_object(@table, {:_, :_, owner, :_}) do
      release(token)
      if is_pid(pid), do: Process.exit(pid, :kill)
    end

    :ok
  end

  def transition({:release_server, server}) do
    ensure_table()

    for {token, ^server, _owner, pid} <- :ets.match_object(@table, {:_, server, :_, :_}) do
      release(token)
      if is_pid(pid), do: Process.exit(pid, :kill)
    end

    :ets.delete(@table, {:count, server})
    :ok
  end

  defp ensure_table,
    do:
      Abyss.TableOwner.ensure_table(@table, [:named_table, :public, :set, write_concurrency: true])
end
