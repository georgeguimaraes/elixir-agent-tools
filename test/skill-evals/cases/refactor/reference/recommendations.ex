defmodule SkillEval.Recommendations do
  def load(fetch, id), do: recommendations(fetch.(id))

  def recommendations(result) do
    case result do
      {:ok, nil} -> nil
      {:ok, run} -> run.recommendations
    end
  end
end
