#!/usr/bin/env elixir
# Summarize completed skill-eval records without treating missing trials as failures.

Code.require_file("../support/json_pretty.exs", __DIR__)

defmodule Summarize do
  @conditions ~w(baseline corrected pruned)

  @limitations [
    "Six audit-selected tasks and three planned repetitions per condition give limited evidence, not a held-out generalization result.",
    "Guidance was loaded explicitly. These trials do not measure skill discovery or routing.",
    "Baseline has common task and verification instructions. It is not an instruction-free model.",
    "Missing records are not counted as failures. Invalid agent runs are reported separately from valid-run pass counts.",
    "Time and token medians use valid runs with available metrics, including valid runs that failed grading. Total tokens are input plus output, without subtracting cached input. They are not a billing estimate.",
    "Hidden checks cover the stated cases, not every possible implementation defect. Controls establish that these checks distinguish the seed from the reference."
  ]

  def read_json(path), do: path |> File.read!() |> JSON.decode!()

  def provenance(path) do
    {:obj,
     [
       {"path", Path.expand(path)},
       {"sha256", :sha256 |> :crypto.hash(File.read!(path)) |> Base.encode16(case: :lower)}
     ]}
  end

  # Python's `type(v) in (int, float)`: booleans and nil are not metrics.
  defp number?(v), do: is_integer(v) or is_float(v)

  def median([]), do: nil

  def median(values) do
    sorted = Enum.sort(values)
    count = length(sorted)
    middle = div(count, 2)

    if rem(count, 2) == 1 do
      Enum.at(sorted, middle)
    else
      (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2
    end
  end

  def metric(values) do
    numbers = Enum.filter(values, &number?/1)
    {:obj, [{"median", median(numbers)}, {"samples", length(numbers)}]}
  end

  def aggregate(rows, expected) do
    valid = Enum.filter(rows, &(Map.get(&1, "valid_run") == true))
    usage = Enum.map(valid, &Map.get(&1, "usage", %{}))

    tokens =
      for u <- usage,
          is_integer(u["input_tokens"]) and is_integer(u["output_tokens"]),
          do: u["input_tokens"] + u["output_tokens"]

    {:obj,
     [
       {"observed", length(rows)},
       {"expected", expected},
       {"missing", if(expected, do: expected - length(rows))},
       {"valid", length(valid)},
       {"invalid_or_unknown_validity", length(rows) - length(valid)},
       {"passed", Enum.count(valid, &(Map.get(&1, "passed") == true))},
       {"agent_seconds", metric(Enum.map(valid, &Map.get(&1, "agent_seconds")))},
       {"input_tokens", metric(Enum.map(usage, &Map.get(&1, "input_tokens")))},
       {"cached_input_tokens", metric(Enum.map(usage, &Map.get(&1, "cached_input_tokens")))},
       {"output_tokens", metric(Enum.map(usage, &Map.get(&1, "output_tokens")))},
       {"total_tokens", metric(tokens)}
     ]}
  end

  defp at({:obj, pairs}, key) do
    {_, value} = Enum.find(pairs, fn {k, _} -> k == key end)
    value
  end

  # Python's f"{value:,.1f}" with a trailing ".0" removed.
  def display(nil), do: "n/a"

  def display(value) do
    text = :erlang.float_to_binary(value / 1, decimals: 1)
    {sign, digits} = if String.starts_with?(text, "-"), do: {"-", binary_slice(text, 1..-1//1)}, else: {"", text}
    [whole, fraction] = String.split(digits, ".")

    grouped =
      whole
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map_join(",", &Enum.join/1)
      |> String.reverse()

    sign <> String.trim_trailing(grouped <> "." <> fraction, ".0")
  end

  def run(opts) do
    results_path = opts[:results]
    controls_path = opts[:controls]
    output = opts[:output]
    protocol_path = opts[:protocol] || Path.join(Path.dirname(results_path), "protocol.json")

    rows = read_json(results_path)
    controls = read_json(controls_path)

    unless is_list(rows) and is_list(controls) do
      raise "Results and controls must be JSON arrays"
    end

    protocol = if protocol_path && File.exists?(protocol_path), do: read_json(protocol_path), else: %{}

    identifiers = Enum.map(rows, &{&1["case"], &1["condition"], &1["repeat"]})
    if length(Enum.uniq(identifiers)) != length(identifiers), do: raise("Duplicate trial records")
    if Enum.any?(rows, &(&1["condition"] not in @conditions)), do: raise("Unknown condition")

    if Enum.any?(rows, &(Map.get(&1, "passed") == true and Map.get(&1, "valid_run") != true)) do
      raise "A passing record must explicitly be valid"
    end

    planned = Enum.map(Map.get(protocol, "trials", []), &List.to_tuple/1)
    if length(Enum.uniq(planned)) != length(planned), do: raise("Duplicate trials in protocol")

    if planned != [] and not MapSet.subset?(MapSet.new(identifiers), MapSet.new(planned)) do
      raise "Observed trial absent from protocol"
    end

    control_ids = Enum.map(controls, &{&1["case"], &1["reference"]})
    if length(Enum.uniq(control_ids)) != length(control_ids), do: raise("Duplicate control records")

    cases =
      ((rows ++ controls) |> Enum.map(& &1["case"]))
      |> Enum.concat(Enum.map(planned, &elem(&1, 0)))
      |> Enum.uniq()
      |> Enum.sort()

    planned_counts = Enum.frequencies(Enum.map(planned, fn {c, cond, _} -> {c, cond} end))

    cells =
      for kase <- cases do
        conditions =
          for condition <- @conditions do
            matching = Enum.filter(rows, &(&1["case"] == kase and &1["condition"] == condition))
            expected = if planned != [], do: Map.get(planned_counts, {kase, condition}, 0)
            {condition, aggregate(matching, expected)}
          end

        {kase, {:obj, conditions}}
      end

    totals =
      for condition <- @conditions do
        matching = Enum.filter(rows, &(&1["condition"] == condition))
        expected = if planned != [], do: Enum.count(planned, &(elem(&1, 1) == condition))
        {condition, aggregate(matching, expected)}
      end

    control_summary =
      for kase <- cases do
        records = Enum.filter(controls, &(&1["case"] == kase))

        complete =
          MapSet.new(records, & &1["reference"]) == MapSet.new([false, true])

        expected_outcomes =
          Enum.all?(records, fn r ->
            is_integer(r["tests"]) and r["tests"] > 0 and Map.get(r, "passed") == r["reference"]
          end)

        {kase,
         {:obj,
          [
            {"complete", complete},
            {"expected_outcomes", expected_outcomes},
            {"records", records}
          ]}}
      end

    inputs =
      [{"results", provenance(results_path)}, {"controls", provenance(controls_path)}] ++
        for {label, path} <- [
              {"protocol", protocol_path},
              {"frozen_inputs", Path.join(Path.dirname(results_path), "manifest.json")},
              {"control_inputs", Path.join(Path.dirname(controls_path), "controls_manifest.json")}
            ],
            path && File.exists?(path) do
          {label, provenance(path)}
        end

    evidence =
      {:obj,
       [
         {"inputs", {:obj, inputs}},
         {"protocol", protocol},
         {"per_case", {:obj, cells}},
         {"totals", {:obj, totals}},
         {"controls", {:obj, control_summary}},
         {"limitations", @limitations},
         {"trials", rows}
       ]}

    File.mkdir_p!(output)
    File.write!(Path.join(output, "evidence.json"), Pretty.encode(evidence) <> "\n")

    File.write!(Path.join(output, "summary.md"), markdown(rows, planned, protocol, cases, cells, totals, control_summary, inputs, output))

    {Path.join(output, "summary.md"), Path.join(output, "evidence.json")}
  end

  defp markdown(rows, planned, protocol, cases, cells, totals, control_summary, inputs, output) do
    planned_total = if planned != [], do: Integer.to_string(length(planned)), else: "unknown"

    header = [
      "# Astra skill evaluation",
      "",
      "Observed #{length(rows)} trial records. Planned total: #{planned_total}. " <>
        "Model: #{Map.get(protocol, "model", "not recorded in protocol")}. " <>
        "Reasoning: #{Map.get(protocol, "reasoning_effort", "not recorded in protocol")}.",
      ""
    ]

    retries = Enum.count(rows, &(Map.get(&1, "source_phase") == "retry"))

    retry_note =
      if retries > 0 do
        [
          "This accepted sample includes #{retries} separate retries of invalid original runs. " <>
            "The [original records](original-results.json) and [retry records](retry-results.json) " <>
            "are preserved separately. The table below describes the accepted sample only.",
          ""
        ]
      else
        []
      end

    case_table =
      [
        "Each cell is **passed / observed (valid runs)**. Missing runs are shown below.",
        "",
        "| Case | Baseline | Corrected | Pruned |",
        "|---|---:|---:|---:|"
      ] ++
        for kase <- cases do
          cell = Enum.find_value(cells, fn {k, v} -> if k == kase, do: v end)

          values =
            for condition <- @conditions do
              stats = at(cell, condition)
              "#{at(stats, "passed")}/#{at(stats, "observed")} (#{at(stats, "valid")} valid)"
            end

          "| #{kase} | " <> Enum.join(values, " | ") <> " |"
        end

    totals_table =
      [
        "",
        "Medians below include valid runs only. Metric sample counts and per-case medians are in [evidence.json](evidence.json).",
        "",
        "| Condition | Passed / valid | Invalid or unknown | Missing | Median seconds | Median input tokens | Median output tokens | Median total tokens |",
        "|---|---:|---:|---:|---:|---:|---:|---:|"
      ] ++
        for {condition, stats} <- totals do
          values =
            [
              "#{at(stats, "passed")}/#{at(stats, "valid")}",
              Integer.to_string(at(stats, "invalid_or_unknown_validity")),
              display(at(stats, "missing"))
            ] ++
              for key <- ~w(agent_seconds input_tokens output_tokens total_tokens) do
                display(at(at(stats, key), "median"))
              end

          "| #{condition} | " <> Enum.join(values, " | ") <> " |"
        end

    controls_table =
      ["", "Controls:", "", "| Case | Seed failed and reference passed with tests observed |", "|---|---|"] ++
        for {kase, record} <- control_summary do
          status =
            if at(record, "complete") and at(record, "expected_outcomes"),
              do: "yes",
              else: "not established"

          "| #{kase} | #{status} |"
        end

    limitations = ["", "Limitations:", ""] ++ Enum.map(@limitations, &"- #{&1}")

    provenance_lines =
      ["", "Input provenance:", ""] ++
        for {label, info} <- inputs do
          path = at(info, "path")
          link = if Path.dirname(path) == Path.expand(output), do: Path.basename(path), else: path
          "- [#{label}](<#{link}>) SHA-256 `#{at(info, "sha256")}`"
        end

    footer = [
      "",
      "[Machine-readable evidence](evidence.json) includes individual trial records, control records, and the recorded protocol.",
      ""
    ]

    Enum.join(
      header ++
        retry_note ++
        case_table ++ totals_table ++ controls_table ++ limitations ++ provenance_lines ++ footer,
      "\n"
    )
  end
end

{opts, _, _} =
  OptionParser.parse(System.argv(),
    strict: [results: :string, controls: :string, output: :string, protocol: :string]
  )

for required <- [:results, :controls, :output] do
  unless opts[required], do: raise("--#{required} is required")
end

{summary, evidence} = Summarize.run(opts)
IO.puts(summary)
IO.puts(evidence)
