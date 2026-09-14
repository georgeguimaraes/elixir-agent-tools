defmodule SkillEval.RecommendationsPublicTest do
  use ExUnit.Case, async: true
  alias SkillEval.Recommendations

  test "loads the selected recommendations" do
    fetch = fn 7 -> {:ok, %{recommendations: ["one", "two"]}} end
    assert Recommendations.load(fetch, 7) == ["one", "two"]
  end

  test "no run has no recommendations" do
    assert Recommendations.load(fn _ -> {:ok, nil} end, 7) == nil
  end
end
