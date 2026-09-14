ExUnit.start()

defmodule SkillEval.TestStatusClient do
  def fetch(_operation_id), do: Process.get(:status_response, :pending)
end

Application.put_env(:skill_eval, :status_client, SkillEval.TestStatusClient)
Application.put_env(:skill_eval, :clock, fn -> Process.get(:status_now) end)
