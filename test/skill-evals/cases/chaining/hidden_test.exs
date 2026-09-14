defmodule SkillEval.ExportAtomicityTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: SkillEval.Repo
  alias SkillEval.{Export, Exports, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    %{export: Repo.insert!(%Export{})}
  end

  test "invalid scheduling rolls back the saved export", %{export: export} do
    assert {:error, %Ecto.Changeset{valid?: false}} =
      Exports.finish(export, %{file_path: "exports/report.csv"}, priority: -1)
    persisted = Repo.get!(Export, export.id)
    assert persisted.status == "pending"
    assert persisted.file_path == nil
    refute_enqueued worker: SkillEval.NotifyWorker, args: %{export_id: export.id}
  end

  test "invalid export does not enqueue a notification", %{export: export} do
    assert {:error, %Ecto.Changeset{valid?: false}} = Exports.finish(export, %{file_path: ""})
    assert Repo.get!(Export, export.id).status == "pending"
    refute_enqueued worker: SkillEval.NotifyWorker, args: %{export_id: export.id}
  end

  test "valid custom queue reaches the inserted job", %{export: export} do
    assert {:ok, _} = Exports.finish(export, %{file_path: "exports/custom.csv"}, queue: "priority")
    assert_enqueued worker: SkillEval.NotifyWorker, args: %{export_id: export.id}, queue: "priority"
  end
end
