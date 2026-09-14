ExUnit.start()
Application.put_env(:skill_eval, SkillEval.Repo,
  url: System.fetch_env!("EVAL_DATABASE_URL"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10
)
{:ok, _} = SkillEval.Repo.start_link()
Ecto.Adapters.SQL.query!(SkillEval.Repo, "CREATE TABLE IF NOT EXISTS entries (value text NOT NULL)", [])
Ecto.Adapters.SQL.Sandbox.mode(SkillEval.Repo, :manual)
