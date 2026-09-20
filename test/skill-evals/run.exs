#!/usr/bin/env elixir
# Run isolated, paired skill evaluations with executable hidden checks.
#
# Ported from run.py. The Python original that produced results/2026-09-05 is kept
# beside those results so that frozen run stays reproducible.
#
# One intentional difference from the Python original: trial shuffling uses Erlang's
# :rand rather than CPython's Mersenne Twister, so the same seed yields a different
# (but still deterministic) trial order. Order only decorrelates scheduling.

Code.require_file("../support/json_pretty.exs", __DIR__)
Code.require_file("../support/proc.exs", __DIR__)

defmodule Eval do
  @root __DIR__

  @cases [
    {"refactor", ["elixir"]},
    {"otp", ["elixir", "otp"]},
    {"sandbox", ["elixir", "ecto"]},
    {"channel", ["elixir", "phoenix"]},
    {"polling", ["elixir", "oban"]},
    {"chaining", ["elixir", "ecto", "oban"]}
  ]

  @conditions ["baseline", "corrected", "pruned"]
  @skills ["elixir", "ecto", "otp", "phoenix", "oban"]
  @db_cases ["sandbox", "chaining"]
  @model "gpt-6-astra"
  @shuffle_seed 20_260_905

  @protected ~w(mix.exs mix.lock test/public_test.exs test/test_helper.exs .formatter.exs .tool-versions)

  @common """
  Work in the current project only. Implement the requested change in lib/.
  Preserve the public interfaces except where the task requests a change. Do not change
  the existing tests, dependency sources, or build configuration. Dependencies are already
  downloaded. Run relevant checks using unbuffer mix. You may consult installed dependency
  source or public documentation when useful. Do not install or read global agent skills.
  No git operations are needed. Finish with a concise description of the change and checks.
  """

  def root, do: @root
  def cases, do: @cases
  def case_names, do: Enum.map(@cases, &elem(&1, 0))
  def conditions, do: @conditions
  def shuffle_seed, do: @shuffle_seed
  def skills, do: @skills

  def digest(path), do: :sha256 |> :crypto.hash(File.read!(path)) |> Base.encode16(case: :lower)

  defp copy_tree(source, destination) do
    File.mkdir_p!(destination)
    {_, 0} = System.cmd("cp", ["-R", Path.join(source, "."), destination])
    :ok
  end

  def prepare(opts, name, kase, reference? \\ false) do
    run = Path.join(opts[:output], name)
    File.mkdir_p!(run)
    work = Path.join(run, "project")
    {_, 0} = System.cmd("cp", ["-cR", opts[:base], work])
    source = Path.join([@root, "cases", kase])
    copy_tree(Path.join(source, "lib"), Path.join(work, "lib"))

    if reference? do
      reference = Path.join(source, "reference")
      reference = if File.dir?(Path.join(reference, "lib")), do: Path.join(reference, "lib"), else: reference
      copy_tree(reference, Path.join(work, "lib"))
    end

    File.mkdir_p!(Path.join(work, "test"))
    helper = Path.join(source, "test_helper.exs")

    File.write!(
      Path.join(work, "test/test_helper.exs"),
      if(File.exists?(helper), do: File.read!(helper), else: "ExUnit.start()\n")
    )

    File.cp!(Path.join(source, "public_test.exs"), Path.join(work, "test/public_test.exs"))

    File.write!(
      Path.join(work, ".formatter.exs"),
      ~s([inputs: ["mix.exs", "{lib,test}/**/*.{ex,exs}"]]\n)
    )

    db = "eval_" <> (:sha256 |> :crypto.hash(Path.expand(run)) |> Base.encode16(case: :lower) |> binary_slice(0, 16))

    elixir_version = "1.20.1-otp-28"
    erlang_version = "28.5.0.2"

    runtime_bins =
      for {tool, version} <- [{"elixir", elixir_version}, {"erlang", erlang_version}] do
        {where, 0} = System.cmd("asdf", ["where", tool, version])
        Path.join(String.trim(where), "bin")
      end

    env =
      System.get_env()
      |> Map.merge(%{
        "MIX_ENV" => "test",
        "HEX_HOME" => Path.join(Path.dirname(Path.expand(opts[:output])), "hex"),
        "ERL_FLAGS" => "+S 4:4",
        "ASDF_ELIXIR_VERSION" => elixir_version,
        "ASDF_ERLANG_VERSION" => erlang_version,
        "EVAL_DATABASE_URL" => "postgres://skill_eval@127.0.0.1:55439/#{db}"
      })

    env = Map.put(env, "PATH", Enum.join(runtime_bins ++ [env["PATH"]], ":"))

    if kase in @db_cases, do: createdb(db)

    {run, work, env}
  end

  defp createdb(db) do
    {_, 0} = System.cmd("createdb", ["-h", "127.0.0.1", "-p", "55439", "-U", "skill_eval", db], stderr_to_stdout: true)
    :ok
  end

  def save_protected(run, work) do
    digests = for name <- @protected, do: {name, digest(Path.join(work, name))}
    File.write!(Path.join(run, "protected.json"), Pretty.encode({:obj, digests}) <> "\n")
  end

  def grade(opts, kase, run, work, env) do
    source = Path.join([@root, "cases", kase])
    original = Path.join(run, "protected.json") |> File.read!() |> JSON.decode!()

    changed =
      for name <- @protected,
          path = Path.join(work, name),
          not File.exists?(path) or digest(path) != original[name],
          do: name

    grader = Path.join(run, "grader")
    {_, 0} = System.cmd("cp", ["-cR", opts[:base], grader])
    copy_tree(Path.join(work, "lib"), Path.join(grader, "lib"))
    work = grader
    File.mkdir_p!(Path.join(work, "test"))

    env =
      if kase in @db_cases do
        db = (env["EVAL_DATABASE_URL"] |> String.split("/") |> List.last()) <> "_grade"
        createdb(db)
        Map.put(env, "EVAL_DATABASE_URL", "postgres://skill_eval@127.0.0.1:55439/#{db}")
      else
        env
      end

    helper = Path.join(source, "test_helper.exs")

    File.write!(
      Path.join(work, "test/test_helper.exs"),
      if(File.exists?(helper), do: File.read!(helper), else: "ExUnit.start()\n")
    )

    for name <- ["public_test.exs", "hidden_test.exs"] do
      File.cp!(Path.join(source, name), Path.join([work, "test", name]))
    end

    log = Path.join(run, "grade.log")
    {code, elapsed} = Proc.command(["unbuffer", "mix", "test", "--seed", "314159"], work, env, log)

    clean = Regex.replace(~r/\x1b\[[0-9;]*m/, File.read!(log), "")
    counts = Regex.scan(~r/(\d+) tests?, (\d+) failures?/, clean)

    {total, failures} =
      case List.last(counts) do
        [_, total, failures] ->
          {String.to_integer(total), String.to_integer(failures)}

        nil ->
          case List.last(Regex.scan(~r{Result: (\d+)(?:/(\d+))? passed}, clean)) do
            [_, passed] ->
              {String.to_integer(passed), 0}

            [_, passed, ""] ->
              {String.to_integer(passed), 0}

            [_, passed, all] ->
              {String.to_integer(all), String.to_integer(all) - String.to_integer(passed)}

            nil ->
              {nil, nil}
          end
      end

    [
      {"grade_exit", code},
      {"tests", total},
      {"failures", failures},
      {"protected_changes", changed},
      {"passed", code == 0 and is_integer(total) and total > 0 and changed == []},
      {"grade_seconds", elapsed}
    ]
  end

  def run_trial(opts, {kase, condition, repeat}) do
    name = "#{kase}-#{condition}-#{repeat}"
    existing = Path.join([opts[:output], name, "result.json"])

    if File.exists?(existing) do
      JSON.decode!(File.read!(existing))
    else
      {run, work, env} = prepare(opts, name, kase)
      save_protected(run, work)

      prompt = @common <> "\nTask:\n" <> File.read!(Path.join([@root, "cases", kase, "prompt.md"]))

      guidance =
        if condition == "baseline" do
          ""
        else
          skills = @cases |> Enum.find(&(elem(&1, 0) == kase)) |> elem(1)

          Enum.map_join(skills, "\n\n", fn skill ->
            File.read!(Path.join([@root, "conditions", condition, "#{skill}.md"]))
          end)
        end

      settings =
        [
          {"model_reasoning_effort", "high"},
          {"skills.include_instructions", false},
          {"skills.bundled.enabled", false},
          {"project_doc_max_bytes", 0},
          {"features.memories", false},
          {"features.apps", false},
          {"features.external_migration", false},
          {"features.shell_snapshot", false},
          {"allow_login_shell", false},
          {"shell_environment_policy.set.PATH", env["PATH"]},
          {"sandbox_workspace_write.network_access", true},
          {"web_search", "live"},
          {"sqlite_home", Path.join(run, "state")},
          {"log_dir", Path.join(run, "logs")}
        ] ++ if(guidance != "", do: [{"developer_instructions", guidance}], else: [])

      argv =
        [
          "codex",
          "exec",
          "--ignore-user-config",
          "--ephemeral",
          "--skip-git-repo-check",
          "--sandbox",
          "workspace-write",
          "--model",
          @model,
          "--json",
          "-C",
          Path.expand(work)
        ] ++
          Enum.flat_map(settings, fn {k, v} -> ["-c", "#{k}=#{JSON.encode!(v)}"] end) ++
          ["-o", Path.join(run, "answer.md"), prompt]

      File.write!(
        Path.join(run, "input.json"),
        Pretty.encode({:obj, [{"prompt", prompt}, {"settings", {:obj, settings}}]}) <> "\n"
      )

      IO.puts("START #{name}")
      events = Path.join(run, "events.jsonl")
      {code, elapsed} = Proc.command(argv, work, env, events, opts[:timeout])

      {usage, tools, errors} = parse_events(events)

      {_, 0} = System.cmd("cp", ["-R", Path.join(work, "lib"), Path.join(run, "solution")])

      graded = grade(opts, kase, run, work, env)
      valid_run = code == 0 and usage != %{} and errors == []

      result =
        {:obj,
         [
           {"case", kase},
           {"condition", condition},
           {"repeat", repeat},
           {"model", @model},
           {"reasoning", "high"},
           {"agent_exit", code},
           {"agent_seconds", elapsed},
           {"tool_events", tools},
           {"usage", usage},
           {"errors", errors},
           {"guidance_bytes", byte_size(guidance)}
         ] ++
           Enum.map(graded, fn
             {"passed", value} -> {"passed", value and valid_run}
             pair -> pair
           end) ++ [{"valid_run", valid_run}]}

      File.write!(Path.join(run, "result.json"), Pretty.encode(result) <> "\n")

      decoded = JSON.decode!(Pretty.encode(result))

      IO.puts(
        "DONE #{name} passed=#{decoded["passed"]} failures=#{decoded["failures"]} seconds=#{elapsed}"
      )

      decoded
    end
  end

  defp parse_events(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reduce({%{}, 0, []}, fn line, {usage, tools, errors} ->
      case JSON.decode(line) do
        {:ok, event} ->
          usage = if event["type"] == "turn.completed", do: Map.get(event, "usage", %{}), else: usage
          item = Map.get(event, "item", %{})

          tools =
            if event["type"] == "item.completed" and item["type"] != "agent_message",
              do: tools + 1,
              else: tools

          errors = if event["type"] in ["turn.failed", "error"], do: errors ++ [event], else: errors
          {usage, tools, errors}

        _ ->
          {usage, tools, errors}
      end
    end)
  end

  def manifest_of(dirs) do
    for dir <- dirs,
        path <- Path.wildcard(Path.join([@root, dir, "**", "*"]), match_dot: true),
        File.regular?(path),
        into: %{} do
      {Path.relative_to(path, @root), digest(path)}
    end
  end
end

defmodule Main do
  def controls(opts) do
    manifest = Eval.manifest_of(["cases"])

    File.write!(
      Path.join(opts[:output], "controls_manifest.json"),
      Pretty.encode(manifest) <> "\n"
    )

    results =
      for kase <- Eval.case_names(), reference? <- [false, true] do
        name = "control-#{kase}-#{if reference?, do: "reference", else: "seed"}"
        {run, work, env} = Eval.prepare(opts, name, kase, reference?)
        Eval.save_protected(run, work)
        graded = Eval.grade(opts, kase, run, work, env)
        result = {:obj, [{"case", kase}, {"reference", reference?}] ++ graded}
        File.write!(Path.join(run, "result.json"), Pretty.encode(result) <> "\n")
        decoded = JSON.decode!(Pretty.encode(result))
        IO.puts(JSON.encode!(decoded))
        decoded
      end

    File.write!(Path.join(opts[:output], "controls.json"), Pretty.encode(results) <> "\n")

    unless Enum.all?(results, &(&1["passed"] == &1["reference"] and &1["tests"])) do
      raise "Invalid controls"
    end

    :ok
  end

  def run(opts) do
    controls = opts[:controls] |> File.read!() |> JSON.decode!()

    unless length(controls) == length(Eval.case_names()) * 2 and
             Enum.all?(controls, &(&1["passed"] == &1["reference"] and &1["tests"])) do
      raise "Invalid controls"
    end

    checked_cases =
      opts[:controls]
      |> Path.dirname()
      |> Path.join("controls_manifest.json")
      |> File.read!()
      |> JSON.decode!()

    unless Enum.all?(checked_cases, fn {name, value} ->
             path = Path.join(Eval.root(), name)
             File.regular?(path) and Eval.digest(path) == value
           end) do
      raise "Cases changed since controls"
    end

    unless Enum.all?(
             for condition <- ["corrected", "pruned"], skill <- Eval.skills() do
               File.exists?(Path.join([Eval.root(), "conditions", condition, "#{skill}.md"]))
             end
           ) do
      raise "Missing condition guidance"
    end

    manifest =
      Eval.manifest_of(["cases", "conditions"])
      |> Map.put("run.exs", Eval.digest(__ENV__.file))
      |> Map.put("mix.lock", Eval.digest(Path.join(opts[:base], "mix.lock")))

    manifest_path = Path.join(opts[:output], "manifest.json")

    if File.exists?(manifest_path) do
      unless JSON.decode!(File.read!(manifest_path)) == manifest do
        raise "Inputs changed after freezing"
      end
    else
      File.write!(manifest_path, Pretty.encode(manifest) <> "\n")
    end

    trials =
      for repeat <- 1..opts[:repeats], kase <- Eval.case_names(), condition <- Eval.conditions() do
        {kase, condition, repeat}
      end

    :rand.seed(:exsss, {Eval.shuffle_seed(), Eval.shuffle_seed(), Eval.shuffle_seed()})
    trials = Enum.shuffle(trials)

    File.write!(
      Path.join(opts[:output], "protocol.json"),
      Pretty.encode(
        {:obj,
         [
           {"model", "gpt-6-astra"},
           {"reasoning_effort", "high"},
           {"repeats", opts[:repeats]},
           {"workers", opts[:workers]},
           {"timeout_seconds", opts[:timeout]},
           {"shuffle_seed", Eval.shuffle_seed()},
           {"trials", Enum.map(trials, &Tuple.to_list/1)},
           {"controls", opts[:controls]},
           {"scope",
            "Loaded guidance, not skill discovery. Six selected audit-related tasks, no held-out generalization claim."},
           {"tools",
            "Codex shell, file editing, live web search. Personal plugins, skills, memories, and project-doc auto-loading disabled."}
         ]}
      ) <> "\n"
    )

    results =
      trials
      |> Task.async_stream(&Eval.run_trial(opts, &1),
        max_concurrency: opts[:workers],
        timeout: :infinity,
        ordered: true
      )
      |> Enum.map(fn {:ok, result} -> result end)

    File.write!(Path.join(opts[:output], "results.json"), Pretty.encode(results) <> "\n")

    for condition <- Eval.conditions() do
      rows = Enum.filter(results, &(&1["condition"] == condition))
      IO.puts("#{condition} #{Enum.count(rows, &(&1["passed"] == true))} / #{length(rows)}")
    end

    :ok
  end
end

{parsed, positional, _} =
  OptionParser.parse(System.argv(),
    strict: [
      base: :string,
      output: :string,
      repeats: :integer,
      workers: :integer,
      timeout: :integer,
      controls: :string
    ]
  )

opts =
  [
    base: "/private/tmp/astra-skill-eval/base",
    output: "/private/tmp/astra-skill-eval/runs",
    repeats: 3,
    workers: 3,
    timeout: 240,
    controls: "/private/tmp/astra-skill-eval/controls-v4/controls.json"
  ]
  |> Keyword.merge(parsed)

mode = List.first(positional)
unless mode in ["controls", "run"], do: raise("mode must be controls or run")

File.mkdir_p!(opts[:output])

case mode do
  "controls" -> Main.controls(opts)
  "run" -> Main.run(opts)
end
