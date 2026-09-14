defmodule SkillEvals.OtpPublicTest do
  use ExUnit.Case, async: true

  test "successful work returns a value and leaves the server idle" do
    server = start_supervised!(SkillEvals.WorkServer)
    assert SkillEvals.WorkServer.run(server, fn -> 42 end) == {:ok, 42}
    assert SkillEvals.WorkServer.status(server) == :idle
  end
end
