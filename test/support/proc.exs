defmodule Proc do
  @moduledoc """
  Run a command with a timeout, logging stdout and stderr to a file.

  The child is placed in its own session with `setsid` so a timeout can signal the
  whole process group at once, the way `subprocess.Popen(start_new_session=True)`
  plus `os.killpg` does. Signalling the group matters: killing descendants one at a
  time lets a parent shell observe a dead child and run its next command before the
  signal reaches it. macOS ships no `setsid` binary, so perl provides it.
  """

  @setsid ~S|use POSIX (); POSIX::setsid(); exec @ARGV or die "$!"|
  @redirect ~S|exec >"$1" 2>&1; shift; exec "$@"|

  def kill_group(pgid, signal) do
    System.cmd("kill", ["-#{signal}", "--", "-#{pgid}"], stderr_to_stdout: true)
    :ok
  end

  @doc "Every descendant of `pid`, shallowest first, so parents are signalled before their children."
  def descendants(pid) do
    case System.cmd("pgrep", ["-P", to_string(pid)], stderr_to_stdout: true) do
      {out, 0} ->
        children = out |> String.split() |> Enum.map(&String.to_integer/1)
        children ++ Enum.flat_map(children, &descendants/1)

      _ ->
        []
    end
  end

  def kill_tree(pid, signal) do
    for p <- [pid | descendants(pid)] do
      System.cmd("kill", ["-#{signal}", to_string(p)], stderr_to_stdout: true)
    end

    :ok
  end

  def alive?(pid) do
    match?({_, 0}, System.cmd("kill", ["-0", to_string(pid)], stderr_to_stdout: true))
  end

  @doc """
  Start `args` and return a handle, without waiting for it to finish.

  Options: `:cwd`, `:env`, `:stdin` (a file supplying stdin, closed at EOF),
  `:stderr` (a file collecting stderr, keeping it out of the captured stdout) and
  `:setsid` (defaults to false, so the child shares the caller's process group the
  way `subprocess.Popen` does).
  """
  def start(args, opts \\ []) do
    [program | rest] = args
    executable = System.find_executable(program) || raise "command not found: #{program}"
    sh = System.find_executable("sh")

    redirects =
      [
        if(opts[:stdin], do: ~s(exec <"#{opts[:stdin]}";), else: ""),
        if(opts[:stderr], do: ~s(exec 2>"#{opts[:stderr]}";), else: "")
      ]
      |> Enum.join()

    launch = [sh, "-c", redirects <> ~S(exec "$@"), "sh", executable] ++ rest

    {command, launch_args} =
      if opts[:setsid] do
        perl = System.find_executable("perl") || raise "perl is required for setsid"
        {perl, ["-e", @setsid] ++ launch}
      else
        {sh, tl(launch)}
      end

    port =
      Port.open({:spawn_executable, command}, [
        :binary,
        :exit_status,
        :hide,
        {:args, launch_args},
        {:cd, opts[:cwd] || File.cwd!()},
        {:env, Enum.map(opts[:env] || %{}, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)}
      ])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    %{port: port, os_pid: os_pid, stderr: opts[:stderr]}
  end

  @doc "Collect stdout and the exit code, or `:timeout` if the process outlives `timeout` ms."
  def wait(handle, timeout \\ 20_000) do
    collect(handle.port, "", System.monotonic_time(:millisecond) + timeout)
  end

  defp collect(port, acc, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} -> collect(port, acc <> data, deadline)
      {^port, {:exit_status, status}} -> {:ok, status, acc}
    after
      remaining -> :timeout
    end
  end

  def signal(handle, sig), do: kill_tree(handle.os_pid, sig)

  @doc """
  Run `args` in `cwd` with `env`, appending stdout and stderr to `output`.

  Returns `{exit_code, seconds}`. A run that exceeds `timeout` seconds is terminated
  and reported as 124, matching the Python harness and `timeout(1)`.
  """
  def command(args, cwd, env, output, timeout \\ 120) do
    started = System.monotonic_time(:millisecond)
    [program | rest] = args
    executable = System.find_executable(program) || raise "command not found: #{program}"
    perl = System.find_executable("perl") || raise "perl is required to start a new session"
    sh = System.find_executable("sh")

    port =
      Port.open({:spawn_executable, perl}, [
        :binary,
        :exit_status,
        :hide,
        {:args, ["-e", @setsid, sh, "-c", @redirect, "sh", Path.expand(output), executable] ++ rest},
        {:cd, cwd},
        {:env, Enum.map(env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)}
      ])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    code = await(port, os_pid, timeout * 1000)
    {code, Float.round((System.monotonic_time(:millisecond) - started) / 1000, 3)}
  end

  defp await(port, os_pid, timeout) do
    receive do
      {^port, {:exit_status, status}} -> status
    after
      timeout ->
        stop(port, os_pid)
        124
    end
  end

  defp stop(port, os_pid) do
    kill_group(os_pid, "TERM")
    kill_tree(os_pid, "TERM")

    unless reaped?(port, 5_000) do
      kill_group(os_pid, "KILL")
      kill_tree(os_pid, "KILL")
      reaped?(port, 10_000)
    end

    :ok
  end

  defp reaped?(port, timeout) do
    receive do
      {^port, {:exit_status, _}} -> true
    after
      timeout -> false
    end
  end
end
