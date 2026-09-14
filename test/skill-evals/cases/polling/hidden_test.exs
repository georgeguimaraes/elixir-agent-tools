defmodule SkillEval.StatusWorkerDeadlineTest do
  use ExUnit.Case, async: true
  import Oban.Testing, only: [perform_job: 3]

  test "a repeated snooze reaches its time limit with an unchanged attempt" do
    args = %{operation_id: "long-poll", requested_at: 10_000}

    for elapsed <- [0, 30, 300, 899] do
      Process.put(:status_now, 10_000 + elapsed)
      assert {:snooze, _} = perform_job(SkillEval.StatusWorker, args,
        attempt: 1, meta: %{snoozed: div(elapsed, 30)})
    end

    Process.put(:status_now, 10_900)
    assert {:cancel, :expired} = perform_job(SkillEval.StatusWorker, args,
      attempt: 1, meta: %{snoozed: 30})
  end

  test "attempt count does not expire a recent request" do
    Process.put(:status_now, 20_060)
    assert {:snooze, _} = perform_job(SkillEval.StatusWorker,
      %{operation_id: "retried", requested_at: 20_000}, attempt: 7)
  end

  test "temporary errors remain retryable and ready results remain successful" do
    Process.put(:status_now, 30_900)
    args = %{operation_id: "late-response", requested_at: 30_000}
    Process.put(:status_response, {:error, :unavailable})
    assert {:error, :unavailable} = perform_job(SkillEval.StatusWorker, args, attempt: 1)
    Process.put(:status_response, {:ok, "ready"})
    assert {:ok, "ready"} = perform_job(SkillEval.StatusWorker, args, attempt: 1)
  end
end
