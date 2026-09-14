defmodule SkillEval.Repo do
  use Ecto.Repo, otp_app: :skill_eval, adapter: Ecto.Adapters.Postgres
end

defmodule SkillEval.Export do
  use Ecto.Schema

  schema "exports" do
    field :status, :string, default: "pending"
    field :file_path, :string
  end

  def finish_changeset(export, attrs) do
    export
    |> Ecto.Changeset.cast(attrs, [:file_path])
    |> Ecto.Changeset.validate_required([:file_path])
    |> Ecto.Changeset.put_change(:status, "complete")
  end
end

defmodule SkillEval.NotifyWorker do
  use Oban.Worker, queue: :notifications
  @impl true
  def perform(_job), do: :ok
end

defmodule SkillEval.Exports do
  alias SkillEval.{Export, NotifyWorker, Repo}

  def finish(export, attrs, job_opts \\ []) do
    Repo.transact(fn ->
      with {:ok, updated} <- Repo.update(Export.finish_changeset(export, attrs)),
           {:ok, _job} <- Oban.insert(NotifyWorker.new(%{export_id: updated.id}, job_opts)) do
        {:ok, updated}
      end
    end)
  end
end
