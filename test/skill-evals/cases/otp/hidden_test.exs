defmodule SkillEvals.OtpHiddenTest do
  use ExUnit.Case, async: true

  defp caller(fun) do
    parent = self()
    token = make_ref()

    pid =
      spawn(fn ->
        result =
          try do
            fun.()
          catch
            :exit, reason -> {:caller_exit, reason}
          end

        send(parent, {token, result})
      end)

    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
    token
  end

  test "work does not block status or busy rejection, and completion restores availability" do
    server = start_supervised!(SkillEvals.WorkServer)
    parent = self()

    token =
      caller(fn ->
        SkillEvals.WorkServer.run(server, fn ->
          send(parent, {:work_started, self()})

          receive do
            :finish -> :completed
          end
        end)
      end)

    assert_receive {:work_started, worker}, 1_000
    on_exit(fn -> if Process.alive?(worker), do: Process.exit(worker, :kill) end)

    try do
      status = caller(fn -> SkillEvals.WorkServer.status(server) end)
      assert_receive {^status, :busy}, 500
      second = caller(fn -> SkillEvals.WorkServer.run(server, fn -> :unexpected end) end)
      assert_receive {^second, {:error, :busy}}, 500
    after
      send(worker, :finish)
    end

    assert_receive {^token, {:ok, :completed}}, 1_000
    assert SkillEvals.WorkServer.status(server) == :idle
    assert SkillEvals.WorkServer.run(server, fn -> :next end) == {:ok, :next}
  end

  test "a work exit is reported to its caller and does not replace the server" do
    server = start_supervised!(SkillEvals.WorkServer)
    ref = Process.monitor(server)
    token = caller(fn -> SkillEvals.WorkServer.run(server, fn -> exit(:work_failed) end) end)

    assert_receive {^token, {:error, {:exit, :work_failed}}}, 1_000
    refute_received {:DOWN, ^ref, :process, ^server, _reason}
    assert Process.alive?(server)
    assert SkillEvals.WorkServer.status(server) == :idle
    assert SkillEvals.WorkServer.run(server, fn -> :recovered end) == {:ok, :recovered}
    Process.demonitor(ref, [:flush])
  end

  test "an exception in work becomes an error and leaves the original server usable" do
    server = start_supervised!(SkillEvals.WorkServer)
    token = caller(fn -> SkillEvals.WorkServer.run(server, fn -> raise "work exploded" end) end)
    assert_receive {^token, {:error, {:exit, reason}}}, 1_000
    assert {%RuntimeError{message: "work exploded"}, stacktrace} = reason
    assert is_list(stacktrace)
    assert Process.alive?(server)
    assert SkillEvals.WorkServer.run(server, fn -> :recovered end) == {:ok, :recovered}
  end
end
