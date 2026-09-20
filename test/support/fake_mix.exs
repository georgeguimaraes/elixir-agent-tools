#!/usr/bin/env elixir
# Stands in for `mix` while the hook tests run. Records every invocation as a JSON
# line so the tests can assert which projects and paths a hook checked, and can
# optionally stall, spawn a stubborn descendant, or fail with canned output.
#
# Driven by environment variables:
#   FAKE_MIX_LOG        file that receives one JSON record per phase (required)
#   FAKE_MIX_DELAY      seconds to sleep between the start and end records
#   FAKE_MIX_CHILD_PID  handled by the shim that launches this script, which spawns a
#                       stubborn descendant in this process group before exec-ing here
#
# Per-project behaviour comes from `.fake-mix.json` in the working directory:
#   {"format": {"code": 1, "output": "..."}}

[action | _] = args = System.argv()
project = File.cwd!()
log_path = System.fetch_env!("FAKE_MIX_LOG")

record = %{"cwd" => project, "args" => args, "pid" => System.pid() |> String.to_integer()}

log = fn phase ->
  line = JSON.encode!(Map.put(record, "phase", phase)) <> "\n"
  File.open!(log_path, [:append, :binary], &IO.binwrite(&1, line))
end

log.("start")

case System.get_env("FAKE_MIX_DELAY") do
  nil -> :ok
  delay ->
    {seconds, _} = Float.parse(delay)
    Process.sleep(round(seconds * 1000))
end

behaviour = Path.join(project, ".fake-mix.json")

result =
  if File.exists?(behaviour) do
    behaviour |> File.read!() |> JSON.decode!() |> Map.get(action, %{})
  else
    %{}
  end

case result["output"] do
  nil -> :ok
  output -> IO.puts(output)
end

log.("end")
System.halt(Map.get(result, "code", 0))
