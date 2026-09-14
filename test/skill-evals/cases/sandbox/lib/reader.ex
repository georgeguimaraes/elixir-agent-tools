defmodule SkillEval.Repo do
  use Ecto.Repo, otp_app: :skill_eval, adapter: Ecto.Adapters.Postgres
end

defmodule SkillEval.Reader do
  use GenServer

  def start_link, do: GenServer.start_link(__MODULE__, nil)
  def entries(pid), do: GenServer.call(pid, :entries)

  @impl true
  def init(nil), do: {:ok, nil}

  @impl true
  def handle_call(:entries, _from, state) do
    %{rows: rows} = Ecto.Adapters.SQL.query!(SkillEval.Repo, "SELECT value FROM entries ORDER BY value", [])
    {:reply, {self(), List.flatten(rows)}, state}
  end
end

defmodule SkillEval.TestSupport do
  def start_reader do
    SkillEval.Reader.start_link()
  end
end
