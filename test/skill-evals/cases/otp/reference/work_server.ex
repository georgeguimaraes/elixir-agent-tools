defmodule SkillEvals.WorkServer do
  use GenServer

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, :idle, opts)
  def run(server, work), do: GenServer.call(server, {:run, work}, :infinity)
  def status(server), do: GenServer.call(server, :status)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:status, _from, :idle), do: {:reply, :idle, :idle}
  def handle_call(:status, _from, state), do: {:reply, :busy, state}

  def handle_call({:run, work}, from, :idle) do
    owner = self()
    token = make_ref()
    {pid, ref} = spawn_monitor(fn -> send(owner, {token, work.()}) end)
    {:noreply, %{pid: pid, ref: ref, token: token, from: from}}
  end

  def handle_call({:run, _work}, _from, state), do: {:reply, {:error, :busy}, state}

  @impl true
  def handle_info({token, value}, %{token: token, ref: ref, from: from}) do
    Process.demonitor(ref, [:flush])
    GenServer.reply(from, {:ok, value})
    {:noreply, :idle}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{ref: ref, from: from}) do
    GenServer.reply(from, {:error, {:exit, reason}})
    {:noreply, :idle}
  end
end
