defmodule SkillEval.ReaderIsolationTest do
  use ExUnit.Case, async: true

  test "simultaneous owners retain separate transactions and reader processes" do
    parent = self()

    tasks = for value <- ["first", "second"] do
      Task.async(fn ->
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(SkillEval.Repo)
        Ecto.Adapters.SQL.query!(SkillEval.Repo, "INSERT INTO entries (value) VALUES ($1)", [value])
        {:ok, reader} = SkillEval.TestSupport.start_reader()
        send(parent, {:ready, self()})

        try do
          receive do
            :read ->
              assert reader != self()
              assert {^reader, [^value]} = SkillEval.Reader.entries(reader)
          after
            3_000 -> flunk("the other owner could not start concurrently")
          end
        after
          if Process.alive?(reader), do: GenServer.stop(reader)
          Ecto.Adapters.SQL.Sandbox.checkin(SkillEval.Repo)
        end
      end)
    end

    assert_receive {:ready, first}, 3_000
    assert_receive {:ready, second}, 3_000
    send(first, :read)
    send(second, :read)
    Enum.each(tasks, &Task.await(&1, 5_000))
  end
end
