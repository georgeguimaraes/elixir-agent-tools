defmodule SkillEval.ExportPublicTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: SkillEval.Repo
  alias SkillEval.{Export, Exports, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    %{export: Repo.insert!(%Export{})}
  end

  test "finishes an export and schedules its notification", %{export: export} do
    assert {:ok, updated} = Exports.finish(export, %{file_path: "exports/report.csv"})
    assert updated.status == "complete"
    assert Repo.get!(Export, export.id).file_path == "exports/report.csv"
    assert_enqueued worker: SkillEval.NotifyWorker, args: %{export_id: export.id}
  end
end
