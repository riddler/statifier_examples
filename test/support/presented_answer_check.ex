defmodule StatifierExamples.PresentedAnswerCheck do
  @moduledoc """
  Checks a presented answer - what `Riddler.Journey.present/3` returns
  inside `{:ok, ...}` - against the JSON Schema riddler ships for it,
  `priv/schemas/presented-answer.schema.json`.

  The schema is read out of the riddler dependency itself
  (`Application.app_dir/2`), never copied into this app, so the check moves
  with the riddler version `mix.lock` resolves. It is validated with
  `ex_json_schema`, the draft-07 validator this app already uses for the
  block document's schema.

  `config/test.exs` names this module as the
  `:presented_answer_check` of `StatifierExamples.Signup.Journey`, which
  calls `check!/1` on every answer before a view is drawn from it. So the
  Journey tests and the page tests that drive the signup Path check every
  answer they draw without saying so. A check also records the answer's
  `"state"` in the calling process (`checked/0`), so a test can show that
  the check ran, and the whole answer (`answers/0`), so a test can read
  every answer a Journey drew a view from.
  """

  @schema_file "priv/schemas/presented-answer.schema.json"
  @checked_key {__MODULE__, :checked}
  @answers_key {__MODULE__, :answers}

  @doc """
  Where the schema is read from: inside the riddler dependency.
  """
  @spec schema_path() :: String.t()
  def schema_path, do: Application.app_dir(:riddler, @schema_file)

  @doc """
  The schema, decoded and resolved; read from `schema_path/0` once per node.
  """
  @spec schema() :: ExJsonSchema.Schema.Root.t()
  def schema do
    case :persistent_term.get({__MODULE__, :schema}, nil) do
      nil ->
        schema = schema_path() |> File.read!() |> Jason.decode!() |> ExJsonSchema.Schema.resolve()
        :persistent_term.put({__MODULE__, :schema}, schema)
        schema

      schema ->
        schema
    end
  end

  @doc """
  `:ok` for an answer the schema admits, or `{:error, errors}` with the
  validator's errors.
  """
  @spec validate(map()) :: :ok | {:error, list()}
  def validate(answer) when is_map(answer), do: ExJsonSchema.Validator.validate(schema(), answer)

  @doc """
  `:ok` for an answer the schema admits, and records its `"state"`;
  raises `ExUnit.AssertionError` naming every error otherwise.
  """
  @spec check!(map()) :: :ok
  def check!(answer) when is_map(answer) do
    case validate(answer) do
      :ok ->
        Process.put(@checked_key, [Map.get(answer, "state") | checked()])
        Process.put(@answers_key, [answer | answers()])
        :ok

      {:error, errors} ->
        raise ExUnit.AssertionError,
          message:
            "presented answer does not keep to #{@schema_file}: " <>
              inspect(errors) <> "\nanswer: " <> inspect(answer)
    end
  end

  @doc """
  The `"state"` of every answer `check!/1` admitted in the calling process,
  latest first.
  """
  @spec checked() :: [String.t()]
  def checked, do: Process.get(@checked_key, [])

  @doc """
  Every answer `check!/1` admitted in the calling process, latest first.
  """
  @spec answers() :: [map()]
  def answers, do: Process.get(@answers_key, [])
end
