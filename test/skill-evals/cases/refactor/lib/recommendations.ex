defmodule SkillEval.Recommendations do
  def load(fetch, id) do
    case fetch.(id) do
      {:ok, nil} -> nil
      {:ok, run} -> run.recommendations
    end
  end
end
