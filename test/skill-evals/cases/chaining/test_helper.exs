ExUnit.start()
Application.put_env(:skill_eval, SkillEval.Repo,
  url: System.fetch_env!("EVAL_DATABASE_URL"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10
)
{:ok, _} = SkillEval.Repo.start_link()

defmodule SkillEval.SetupMigration do
  use Ecto.Migration
  def up do
    Oban.Migration.up()
    create table(:exports) do
      add :status, :string, null: false, default: "pending"
      add :file_path, :string
    end
  end
end

Ecto.Migrator.up(SkillEval.Repo, 1, SkillEval.SetupMigration, log: false)
Ecto.Adapters.SQL.Sandbox.mode(SkillEval.Repo, :manual)
{:ok, _} = Oban.start_link(repo: SkillEval.Repo, testing: :manual, queues: false, plugins: false)
