defmodule Abyss.SenderPool do
  @moduledoc false

  use Supervisor

  @spec start_link({server_pid :: pid, Abyss.ServerConfig.t()}) :: Supervisor.on_start()
  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg)
  end

  @spec sender_pids(Supervisor.supervisor()) :: [pid()]
  def sender_pids(supervisor) do
    supervisor
    |> Supervisor.which_children()
    |> Enum.reduce([], fn
      {_, sender_pid, _, _}, acc when is_pid(sender_pid) -> [sender_pid | acc]
      _, acc -> acc
    end)
  end

  @impl Supervisor
  @spec init({server_pid :: pid, Abyss.ServerConfig.t()}) ::
          {:ok,
           {Supervisor.sup_flags(),
            [Supervisor.child_spec() | (old_erlang_child_spec :: :supervisor.child_spec())]}}
  def init({server_pid, %Abyss.ServerConfig{num_senders: num_senders} = config}) do
    1..num_senders
    |> Enum.map(
      &Supervisor.child_spec({Abyss.Sender, {&1, server_pid, config}}, id: "sender-#{&1}")
    )
    |> Supervisor.init(strategy: :one_for_one)
  end
end
