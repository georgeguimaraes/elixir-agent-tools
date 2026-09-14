defmodule SkillEval.ReaderPublicTest do
  use ExUnit.Case, async: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(SkillEval.Repo)
    :ok
  end

  test "reader sees the test's inserted record" do
    Ecto.Adapters.SQL.query!(SkillEval.Repo, "INSERT INTO entries (value) VALUES ($1)", ["public"])
    {:ok, reader} = SkillEval.TestSupport.start_reader()
    try do
      assert {^reader, ["public"]} = SkillEval.Reader.entries(reader)
    after
      if Process.alive?(reader), do: GenServer.stop(reader)
    end
  end
end
