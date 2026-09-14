defmodule SkillEval.RecommendationsHiddenTest do
  use ExUnit.Case, async: true
  alias SkillEval.Recommendations

  test "the extracted API handles present and absent values" do
    for result <- [{:ok, nil}, {:ok, %{recommendations: []}}, {:ok, %{recommendations: nil}}, {:ok, %{recommendations: [1]}}] do
      assert Recommendations.recommendations(result) == Recommendations.load(fn _ -> result end, 0)
    end
    assert Recommendations.recommendations({:ok, nil}) == nil
    assert Recommendations.recommendations({:ok, %{recommendations: [1]}}) == [1]
  end

  test "unexpected fetch results preserve the existing failure contract" do
    for result <- [{:error, :unavailable}, :invalid, {:ok, :wrong_shape}] do
      assert catch_error(Recommendations.recommendations(result)) == catch_error(original(result))
      assert catch_error(Recommendations.load(fn _ -> result end, 0)) == catch_error(original(result))
    end
  end

  test "missing recommendation fields remain errors" do
    assert_raise KeyError, fn -> Recommendations.recommendations({:ok, %{id: 1}}) end
    assert_raise KeyError, fn -> Recommendations.load(fn _ -> {:ok, %{id: 1}} end, 0) end
  end

  defp original(result) do
    case result do
      {:ok, nil} -> nil
      {:ok, run} -> run.recommendations
    end
  end
end
