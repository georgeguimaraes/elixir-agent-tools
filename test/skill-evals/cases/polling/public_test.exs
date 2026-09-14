defmodule SkillEval.StatusWorkerPublicTest do
  use ExUnit.Case, async: true
  import Oban.Testing, only: [perform_job: 3]

  test "pending requests are scheduled for another poll" do
    Process.put(:status_now, 1_000)
    assert {:snooze, 30} = perform_job(SkillEval.StatusWorker,
      %{operation_id: "request-1", requested_at: 900}, attempt: 1)
  end

  test "ready requests return their result" do
    Process.put(:status_now, 1_000)
    Process.put(:status_response, {:ok, %{result: 42}})
    assert {:ok, %{result: 42}} = perform_job(SkillEval.StatusWorker,
      %{operation_id: "request-2", requested_at: 900}, attempt: 1)
  end
end
