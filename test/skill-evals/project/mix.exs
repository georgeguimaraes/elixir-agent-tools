defmodule SkillEval.MixProject do
  use Mix.Project

  def project do
    [app: :skill_eval, version: "0.1.0", elixir: "~> 1.20", deps: deps()]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:phoenix, "1.8.13"},
      {:oban, "2.24.1"},
      {:ecto_sql, "3.14.0"},
      {:jason, "~> 1.4"},
      {:postgrex, "~> 0.21"}
    ]
  end
end
