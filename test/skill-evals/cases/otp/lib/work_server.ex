defmodule SkillEvals.WorkServer do
  use GenServer

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, :idle, opts)
  def run(server, work), do: GenServer.call(server, {:run, work}, :infinity)
  def status(server), do: GenServer.call(server, :status)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state, state}

  def handle_call({:run, work}, _from, state) do
    {:reply, {:ok, work.()}, state}
  end
end
