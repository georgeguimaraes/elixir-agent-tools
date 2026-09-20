#!/usr/bin/env elixir
# Exercise installed Mix hooks with Bash and isolated fake Mix projects.
#
#   elixir test/test_mix_hooks.exs

Code.require_file("support/proc.exs", __DIR__)

ExUnit.start(timeout: 120_000)

defmodule MixHooksTest do
  use ExUnit.Case, async: false

  @root Path.expand("..", __DIR__)
  @actions ~w(format compile credo)
  @fake_mix Path.join(__DIR__, "support/fake_mix.exs")

  setup do
    base = physical(make_temp_dir("mix hooks test "))
    on_exit(fn -> File.rm_rf(base) end)

    workspace = Path.join(base, "workspace")
    shell_cwd = Path.join(base, "unrelated shell cwd")
    log = Path.join(base, "mix calls.jsonl")
    bin = Path.join(base, "fake bin")
    tempdir = Path.join(base, "temporary files")
    for dir <- [workspace, shell_cwd, bin, tempdir], do: File.mkdir_p!(dir)

    File.ln_s!("/bin/bash", Path.join(bin, "bash"))

    # The stubborn descendant is spawned here rather than inside the Elixir script:
    # the BEAM starts its own children in a separate session, which would put them
    # outside the process group the hook signals.
    mix = Path.join(bin, "mix")

    File.write!(mix, """
    #!/bin/sh
    if [ -n "$FAKE_MIX_CHILD_PID" ]; then
      bash -c 'trap "" TERM; sleep 60' &
      printf %s "$!" > "$FAKE_MIX_CHILD_PID"
    fi
    exec elixir "#{@fake_mix}" "$@"
    """)

    File.chmod!(mix, 0o755)

    lsof = Path.join(bin, "lsof")
    File.write!(lsof, "#!/bin/bash\nexit 1\n")
    File.chmod!(lsof, 0o755)

    plugins =
      for action <- @actions, into: %{} do
        installed = Path.join([base, "installed plugins", "mix-#{action}"])
        File.mkdir_p!(Path.dirname(installed))
        File.cp_r!(Path.join([@root, "plugins", "mix-#{action}"]), installed)
        {action, installed}
      end

    env =
      System.get_env()
      |> Map.drop(["BASH_ENV", "ENV"])
      |> Map.merge(%{
        "PATH" => bin <> ":" <> System.get_env("PATH"),
        "FAKE_MIX_LOG" => log,
        "TMPDIR" => tempdir
      })

    %{
      base: base,
      workspace: workspace,
      shell_cwd: shell_cwd,
      log: log,
      bin: bin,
      plugins: plugins,
      env: env
    }
  end

  # Resolve symlinks so comparisons against the working directory a process reports
  # (which the OS has already resolved) line up.
  defp physical(path), do: File.cd!(path, &File.cwd!/0)

  defp make_temp_dir(prefix) do
    path = Path.join(System.tmp_dir!(), prefix <> Integer.to_string(System.unique_integer([:positive])))
    File.mkdir_p!(path)
    path
  end

  defp project(context, name, files) do
    dir = Path.join(context.workspace, name)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "mix.exs"), "# fake Mix project\n")

    for file <- files do
      path = Path.join(dir, file)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "# fake source\n")
    end

    dir
  end

  defp event(context, tool_input, tool_name \\ "Edit", cwd \\ nil) do
    %{
      "hook_event_name" => "PostToolUse",
      "tool_name" => tool_name,
      "cwd" => cwd || context.workspace,
      "tool_input" => tool_input
    }
  end

  defp payload(event) when is_binary(event), do: event
  defp payload(event), do: ascii_json(event)

  # Claude Code sends \uXXXX escapes, like Python's json.dumps(ensure_ascii=True).
  defp ascii_json(term) do
    term
    |> JSON.encode!()
    |> String.to_charlist()
    |> Enum.map_join(fn
      c when c < 128 ->
        <<c>>

      c when c <= 0xFFFF ->
        "\\u" <> Base.encode16(<<c::16>>, case: :lower)

      c ->
        rest = c - 0x10000
        high = 0xD800 + div(rest, 0x400)
        low = 0xDC00 + rem(rest, 0x400)
        "\\u" <> Base.encode16(<<high::16>>, case: :lower) <>
          "\\u" <> Base.encode16(<<low::16>>, case: :lower)
    end)
  end

  defp start_hook(context, action, event, opts) do
    installed = context.plugins[action]

    env =
      context.env
      |> Map.put("CLAUDE_PLUGIN_ROOT", installed)
      |> Map.merge(Map.new(opts[:env] || %{}))

    command =
      if opts[:manifest] do
        config = Path.join(installed, "hooks/hooks.json") |> File.read!() |> JSON.decode!()
        handler = config["hooks"]["PostToolUse"] |> hd() |> Map.fetch!("hooks") |> hd()
        ["/bin/bash", "-c", handler["command"]]
      else
        ["/bin/bash", Path.join(installed, "hooks/mix-hook.sh"), action]
      end

    stdin = Path.join(context.base, "stdin-#{System.unique_integer([:positive])}")
    File.write!(stdin, payload(event))
    stderr = stdin <> ".err"

    Proc.start(command, cwd: context.shell_cwd, env: env, stdin: stdin, stderr: stderr)
  end

  defp finish(handle) do
    case Proc.wait(handle, 20_000) do
      :timeout ->
        Proc.signal(handle, "KILL")
        flunk("Hook did not finish within 20 seconds")

      {:ok, code, stdout} ->
        stderr = if handle.stderr && File.exists?(handle.stderr), do: File.read!(handle.stderr), else: ""
        assert code == 0, "hook exited #{code}\nstderr: #{stderr}\nstdout: #{stdout}"

        if String.trim(stdout) == "" do
          ""
        else
          specific = stdout |> JSON.decode!() |> Map.fetch!("hookSpecificOutput")
          assert specific["hookEventName"] == "PostToolUse"
          assert is_binary(specific["additionalContext"])
          specific["additionalContext"]
        end
    end
  end

  defp run_hook(context, action, event, opts \\ []) do
    context |> start_hook(action, event, opts) |> finish()
  end

  defp records(context) do
    if File.exists?(context.log) do
      context.log |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
    else
      []
    end
  end

  defp calls(context), do: Enum.filter(records(context), &(&1["phase"] == "start"))

  defp clear_log(context), do: File.rm(context.log)

  defp checked_paths(calls) do
    for call <- calls, argument <- tl(call["args"]), argument != "--", into: MapSet.new() do
      Path.expand(argument, call["cwd"])
    end
  end

  defp wait_until(condition, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    poll(condition, deadline)
  end

  defp poll(condition, deadline) do
    cond do
      condition.() -> :ok
      System.monotonic_time(:millisecond) >= deadline -> flunk("Timed out waiting for the expected process state")
      true -> Process.sleep(20) && poll(condition, deadline)
    end
  end

  # A reaped-but-unwaited process still answers `kill -0`, so ask for its state too.
  defp process_alive?(pid) do
    case System.cmd("ps", ["-o", "stat=", "-p", to_string(pid)], stderr_to_stdout: true) do
      {out, 0} -> String.trim(out) != "" and not String.starts_with?(String.trim(out), "Z")
      _ -> false
    end
  end

  defp kill_group(pid), do: System.cmd("kill", ["-KILL", "--", "-#{pid}"], stderr_to_stdout: true)

  test "Claude escaped paths use event cwd in standalone plugins", context do
    filename = "lib/spaces \"quote\" \\backslash\ttab café 😀\nline.ex"
    dir = project(context, "project \"quoted\" café", [filename])
    path = Path.join(dir, filename)

    for action <- @actions, {key, tool} <- [{"file_path", "Edit"}, {"filePath", "Write"}] do
      clear_log(context)
      run_hook(context, action, event(context, %{key => filename}, tool, dir), manifest: true)
      calls = calls(context)
      assert length(calls) == 1, "#{action}/#{key}: expected one Mix call, got #{length(calls)}"
      assert hd(calls)["cwd"] == dir

      if action == "compile" do
        assert hd(calls)["args"] == ["compile", "--warnings-as-errors"]
      else
        assert checked_paths(calls) == MapSet.new([path])
      end
    end
  end

  test "Codex patch groups projects and tracks surviving paths", context do
    first = project(context, "first", ["lib/added.ex", "lib/update.ex"])
    second = project(context, "second", ["lib/moved.ex", "test/script.exs"])
    scripts = project(context, "scripts only", ["test/script.exs", "README.md"])

    patch =
      Enum.join(
        [
          "*** Begin Patch",
          "*** Add File: first/lib/added.ex",
          "+# added",
          "+*** Delete File: ignored.ex",
          "*** Update File: first/lib/update.ex",
          "@@",
          "-# old",
          "+# updated",
          "*** Delete File: first/lib/deleted.ex",
          "*** Update File: first/lib/old.ex",
          "*** Move to: second/lib/moved.ex",
          "@@",
          "-# old",
          "+# moved",
          "*** Update File: second/test/script.exs",
          "@@",
          "+# test",
          "*** Update File: scripts only/test/script.exs",
          "@@",
          "+# test",
          "*** Update File: scripts only/README.md",
          "@@",
          "+docs",
          "*** End Patch"
        ],
        "\n"
      )

    event = event(context, %{"command" => patch}, "apply_patch")

    expected =
      MapSet.new([
        Path.join(first, "lib/added.ex"),
        Path.join(first, "lib/update.ex"),
        Path.join(second, "lib/moved.ex"),
        Path.join(second, "test/script.exs"),
        Path.join(scripts, "test/script.exs")
      ])

    for action <- @actions do
      clear_log(context)
      run_hook(context, action, event)
      calls = calls(context)

      if action == "compile" do
        assert Enum.sort(Enum.map(calls, & &1["cwd"])) == Enum.sort([first, second])
        assert Enum.all?(calls, &(&1["args"] == ["compile", "--warnings-as-errors"]))
      else
        assert checked_paths(calls) == expected, "#{action}: wrong paths"
        checked = Enum.sum(for call <- calls, do: Enum.count(tl(call["args"]), &(&1 != "--")))
        assert checked == MapSet.size(expected)
      end
    end
  end

  test "delete and move away from Elixir still compile old projects", context do
    deleted = project(context, "deleted", ["lib/keep.txt"])
    moved = project(context, "moved", ["lib/renamed.txt"])

    patch =
      Enum.join(
        [
          "*** Begin Patch",
          "*** Delete File: deleted/lib/gone.ex",
          "*** Update File: moved/lib/old.ex",
          "*** Move to: moved/lib/renamed.txt",
          "@@",
          "-# old",
          "+# moved",
          "*** End Patch"
        ],
        "\n"
      )

    event = event(context, %{"command" => patch}, "apply_patch")
    run_hook(context, "compile", event)
    assert Enum.sort(Enum.map(calls(context), & &1["cwd"])) == Enum.sort([deleted, moved])

    for action <- ["format", "credo"] do
      clear_log(context)
      run_hook(context, action, event)
      assert calls(context) == []
    end
  end

  test "Codex CRLF patch checks changed files", context do
    dir = project(context, "crlf", ["lib/changed.ex"])

    patch =
      Enum.join(
        ["*** Begin Patch", "*** Update File: crlf/lib/changed.ex", "@@", "-# old", "+# new", "*** End Patch", ""],
        "\r\n"
      )

    event = event(context, %{"command" => patch}, "apply_patch")

    for action <- @actions do
      clear_log(context)
      run_hook(context, action, event)
      assert length(calls(context)) == 1, "#{action}: expected one Mix call"

      if action != "compile" do
        assert checked_paths(calls(context)) == MapSet.new([Path.join(dir, "lib/changed.ex")])
      end
    end
  end

  test "failures reach the model and do not skip other projects", context do
    broken = project(context, "broken", ["lib/file.ex"])
    healthy = project(context, "healthy", ["lib/file.ex"])

    behaviour =
      for action <- @actions, into: %{} do
        {action, %{"code" => 1, "output" => "#{action}: bad \"quoted\" value\nsecond line"}}
      end

    File.write!(Path.join(broken, ".fake-mix.json"), JSON.encode!(behaviour))

    patch =
      Enum.join(
        [
          "*** Begin Patch",
          "*** Update File: broken/lib/file.ex",
          "@@",
          "+# changed",
          "*** Update File: healthy/lib/file.ex",
          "@@",
          "+# changed",
          "*** End Patch"
        ],
        "\n"
      )

    for action <- @actions do
      clear_log(context)
      message = run_hook(context, action, event(context, %{"command" => patch}, "apply_patch"))
      assert message =~ "#{action}: bad \"quoted\" value\nsecond line"
      assert Enum.sort(Enum.map(calls(context), & &1["cwd"])) == Enum.sort([broken, healthy])
    end
  end

  test "unrelated or malformed events do not run Mix", context do
    dir = project(context, "project", ["README.md", "lib/source.ex"])
    outside = Path.join(context.workspace, "outside.ex")
    File.write!(outside, "# outside a Mix project\n")

    events = [
      event(context, %{"file_path" => Path.join(dir, "README.md")}),
      event(context, %{"command" => "echo hello"}, "Bash"),
      event(context, %{"file_path" => outside}),
      event(context, %{"content" => JSON.encode!(%{"file_path" => Path.join(dir, "lib/source.ex")})}),
      event(context, %{"command" => "*** Begin Patch\n*** End Patch"}, "apply_patch"),
      ~s({"tool_input":)
    ]

    for action <- @actions, {event, index} <- Enum.with_index(events) do
      run_hook(context, action, event)
      assert calls(context) == [], "#{action}: event #{index} ran Mix"
    end
  end

  test "compile ignores scripts but format and credo check them", context do
    dir = project(context, "scripts", ["test/script.exs"])
    event = event(context, %{"file_path" => Path.join(dir, "test/script.exs")})

    run_hook(context, "compile", event)
    assert calls(context) == []

    for action <- ["format", "credo"] do
      clear_log(context)
      run_hook(context, action, event)
      assert checked_paths(calls(context)) == MapSet.new([Path.join(dir, "test/script.exs")])
    end
  end

  test "credo absence is distinct from project failure", context do
    dir = project(context, "credo", ["lib/source.ex"])
    event = event(context, %{"file_path" => Path.join(dir, "lib/source.ex")})
    behaviour = Path.join(dir, ".fake-mix.json")

    absent = ~S|** (Mix) The task "credo" could not be found|
    File.write!(behaviour, JSON.encode!(%{"credo" => %{"code" => 1, "output" => absent}}))
    message = run_hook(context, "credo", event)
    refute String.downcase(message) =~ "failed"
    assert length(calls(context)) == 1

    clear_log(context)
    failure = "** (Mix) Can't continue due to errors on dependencies"
    File.write!(behaviour, JSON.encode!(%{"credo" => %{"code" => 1, "output" => failure}}))
    message = run_hook(context, "credo", event)
    assert message =~ failure
    assert length(calls(context)) == 1
  end

  test "concurrent plugins serialize Mix for one project", context do
    dir = project(context, "concurrent", ["lib/source.ex"])
    event = event(context, %{"file_path" => Path.join(dir, "lib/source.ex")})

    handles =
      for action <- @actions do
        start_hook(context, action, event, env: %{"FAKE_MIX_DELAY" => "0.3"})
      end

    for handle <- handles, do: finish(handle)

    records = records(context)
    assert length(records) == 6

    active =
      Enum.reduce(records, MapSet.new(), fn record, active ->
        if record["phase"] == "start" do
          assert MapSet.size(active) == 0, "Overlapping Mix commands: #{inspect(records)}"
          MapSet.put(active, record["pid"])
        else
          assert MapSet.member?(active, record["pid"])
          MapSet.delete(active, record["pid"])
        end
      end)

    assert MapSet.size(active) == 0
    assert Enum.sort(Enum.map(calls(context), &hd(&1["args"]))) == Enum.sort(@actions)
  end

  test "alias project paths share a lock", context do
    dir = project(context, "canonical", ["lib/source.ex"])
    alias_path = Path.join(context.workspace, "alias")
    File.ln_s!(dir, alias_path)

    handles =
      for directory <- [dir, alias_path] do
        event = event(context, %{"file_path" => "lib/source.ex"}, "Edit", directory)
        start_hook(context, "format", event, env: %{"FAKE_MIX_DELAY" => "0.3"})
      end

    for handle <- handles, do: finish(handle)

    records = records(context)
    assert Enum.map(records, & &1["phase"]) == ["start", "end", "start", "end"]
    assert Enum.all?(records, &(&1["cwd"] == dir))
  end

  test "timeout kills Mix and descendants and releases the lock", context do
    script = Path.join(context.plugins["format"], "hooks/mix-hook.sh")
    original = File.read!(script)
    shortened = String.replace(original, "format) budget=45 ;;", "format) budget=2 ;;")
    assert shortened != original, "budget line not found in mix-hook.sh"
    File.write!(script, shortened)

    dir = project(context, "timeout", ["lib/source.ex"])
    event = event(context, %{"file_path" => Path.join(dir, "lib/source.ex")})
    marker = Path.join(context.base, "descendant.pid")

    handle =
      start_hook(context, "format", event,
        env: %{"FAKE_MIX_DELAY" => "60", "FAKE_MIX_CHILD_PID" => marker}
      )

    wait_until(fn -> File.exists?(marker) and calls(context) != [] end)
    parent_pid = hd(calls(context))["pid"]
    child_pid = marker |> File.read!() |> String.trim() |> String.to_integer()
    on_exit(fn -> kill_group(parent_pid) end)

    message = finish(handle)
    assert String.downcase(message) =~ "timed out"
    wait_until(fn -> not process_alive?(parent_pid) and not process_alive?(child_pid) end)

    clear_log(context)
    run_hook(context, "format", event)
    assert length(calls(context)) == 1
  end

  test "cancellation kills Mix and descendants and releases the lock", context do
    dir = project(context, "cancelled", ["lib/source.ex"])
    event = event(context, %{"file_path" => Path.join(dir, "lib/source.ex")})
    marker = Path.join(context.base, "descendant.pid")

    handle =
      start_hook(context, "format", event,
        env: %{"FAKE_MIX_DELAY" => "60", "FAKE_MIX_CHILD_PID" => marker}
      )

    wait_until(fn -> File.exists?(marker) and calls(context) != [] end)
    parent_pid = hd(calls(context))["pid"]
    child_pid = marker |> File.read!() |> String.trim() |> String.to_integer()
    on_exit(fn -> kill_group(parent_pid) end)

    Proc.signal(handle, "TERM")
    assert {:ok, 143, _} = Proc.wait(handle, 5_000)
    wait_until(fn -> not process_alive?(parent_pid) and not process_alive?(child_pid) end)

    clear_log(context)
    run_hook(context, "format", event)
    assert length(calls(context)) == 1
  end

  test "BEAM detection matches the exact project path", context do
    dir = project(context, "beam project", ["lib/source.ex"])
    event = event(context, %{"file_path" => Path.join(dir, "lib/source.ex")})

    lsof = Path.join(context.bin, "lsof")
    File.write!(lsof, ~s(#!/bin/bash\nprintf "%s\\n" "p123" "n$FAKE_BEAM_CWD"\n))

    message = run_hook(context, "compile", event, env: %{"FAKE_BEAM_CWD" => dir})
    assert calls(context) == []
    assert String.downcase(message) =~ "skipped"

    run_hook(context, "compile", event, env: %{"FAKE_BEAM_CWD" => dir <> "-other"})
    assert length(calls(context)) == 1
  end
end
