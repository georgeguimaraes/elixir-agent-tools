defmodule SkillEval.StatusWorker do
  use Oban.Worker, queue: :status, max_attempts: 10

  @impl true
  def perform(%Oban.Job{args: args}) do
    client = Application.fetch_env!(:skill_eval, :status_client)

    case client.fetch(args["operation_id"]) do
      {:ok, result} -> {:ok, result}
      :pending ->
        if now() >= args["requested_at"] + 900,
          do: {:cancel, :expired},
          else: {:snooze, 30}
      {:error, reason} -> {:error, reason}
    end
  end

  def now do
    clock = Application.get_env(:skill_eval, :clock, fn -> System.system_time(:second) end)
    clock.()
  end
end
