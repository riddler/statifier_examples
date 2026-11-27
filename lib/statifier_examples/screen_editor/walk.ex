defmodule StatifierExamples.ScreenEditor.Walk do
  @moduledoc """
  The walk from a block document the screen editor holds to the screen
  document riddler reads: `screen_document/1`.

  The blocks compiler turns a block document into a chart, and a screen
  document is not a chart, so the JSON comes from this host walk instead:
  over the committed document, in the order the author placed the blocks,
  answering the decoded JSON map `Riddler.Screens.Document.admit/1` takes.

  ## What it reads

  The document's root is `core.sequence` and its `body` holds the screens
  in order (`StatifierExamples.ScreenEditor`, "The palette"). Each screen
  is a `myapp.screens.screen` block whose `elements` slot holds its
  elements in order, and a `myapp.screens.variant` holds its candidates
  the same way. The walk follows those slots, so a screen's elements come
  out in the order they sit in the slot.

  ## What it answers

  The envelope carries `schema_version` 2, the block document's `id`, and
  its `metadata` when there is any: a version 2 document, which spells a
  screen's children `elements`. A screen carries its `key`, `title` and
  `elements`; an element carries `type` - the block type's name after
  `myapp.screens.` - and the fields its block type declares, copied under
  the same names. A field left blank (`nil`, an empty string, an empty list
  of writes) is left out, as a document that never wrote it would be, while
  `false` is a value and is kept.

  Some fields are written differently in the editor, and the walk turns
  each back into the document's shape:

    * a choice question's `answer_options` rows, `value=Label`, become
      `[%{"value" => value, "label" => label}]` in order, and each of its
      `option_descriptions` rows, `value=Description`, becomes the
      `"description"` of the option it names; `option_descriptions` itself
      is left out, since the document has no such field;
    * a text question's `min` and `max`, written as text, become numbers,
      except under the `date`, `time` and `datetime` formats, where a
      bound is a value in the format's own shape and stays the text it is;
      its `step`, written as text, becomes a number;
    * a question's `checks` rows, `code: condition => message`, become
      `[%{"condition" => condition, "code" => code, "message" => message}]`
      in order (`StatifierExamples.ScreenEditor.Element.checks/1`);
    * a button's `writes` rows, `responses.<path>=value`, become the map
      `%{"responses.<path>" => ["const", value]}`. The value is read as
      JSON when it is JSON - `3`, `true`, `["a", "b"]`, `"12"` - and as
      the text itself when it is not, so `responses.card=family` writes
      the string `"family"`. Two rows that write one path are refused
      rather than letting the second replace the first.

  ## What it refuses

  `{:error, refusals}` lists every block the walk cannot turn into the
  document, each as `{block_id, message}`, in document order: a root that
  is not `core.sequence`, a block in the root's body that is not a screen,
  a block in an `elements` slot that is not an element type, and a row a
  field
  cannot be read from. What the walk answers is not yet checked as a
  document; that is `Riddler.Screens.Document.validate/1`'s job.
  """

  alias StatifierBlocks.Block
  alias StatifierBlocks.Document
  alias StatifierExamples.ScreenEditor

  @prefix "myapp.screens."
  @screen @prefix <> "screen"
  @variant @prefix <> "variant"
  @dated ScreenEditor.TextQuestion.dated_formats()

  @typedoc "One block the walk cannot turn into the document, and why."
  @type refusal :: {Block.id(), String.t()}

  @doc """
  The screen document `document` holds, as the decoded JSON map
  `Riddler.Screens.Document.admit/1` takes, or every refusal.
  """
  @spec screen_document(Document.t()) :: {:ok, map()} | {:error, [refusal()]}
  def screen_document(%Document{root: %Block{type: "core.sequence"} = root} = document) do
    {screens, refusals} = collect(Map.get(root.slots, "body", []), &screen/1)

    case refusals do
      [] -> {:ok, envelope(document, screens)}
      refusals -> {:error, refusals}
    end
  end

  def screen_document(%Document{root: %Block{id: id}}),
    do: {:error, [{id, "the root of a screen document is a core.sequence of screens"}]}

  defp envelope(document, screens) do
    %{"schema_version" => 2, "id" => document.id, "screens" => screens}
    |> put_present("metadata", document.metadata)
  end

  defp screen(%Block{type: @screen} = block) do
    with {:ok, elements} <- elements(block) do
      {:ok, Map.put(fields(block, ["key", "title"]), "elements", elements)}
    end
  end

  defp screen(%Block{id: id}),
    do: {:error, [{id, "a screen document's body holds screens and nothing else"}]}

  defp elements(block) do
    case collect(Map.get(block.slots, "elements", []), &walk_element/1) do
      {elements, []} -> {:ok, elements}
      {_elements, refusals} -> {:error, refusals}
    end
  end

  defp walk_element(%Block{type: @variant} = block) do
    with {:ok, elements} <- elements(block) do
      {:ok, block |> base(["key", "condition"]) |> Map.put("elements", elements)}
    end
  end

  defp walk_element(%Block{type: @prefix <> _name = type} = block) when type != @screen do
    case Map.fetch(modules(), type) do
      {:ok, module} ->
        keys = Enum.map(module.config_schema(block.config), & &1.key)
        block |> base(keys) |> convert(block.id)

      :error ->
        unknown(block)
    end
  end

  defp walk_element(block), do: unknown(block)

  defp unknown(%Block{id: id, type: type}),
    do: {:error, [{id, "#{type} is not an element type a screen holds"}]}

  defp base(%Block{type: @prefix <> name} = block, keys),
    do: Map.put(fields(block, keys), "type", name)

  defp fields(%Block{config: config}, keys) do
    Enum.reduce(keys, %{}, fn key, acc -> put_present(acc, key, Map.get(config, key)) end)
  end

  defp put_present(map, _key, blank) when blank in [nil, "", [], %{}], do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  # The fields the editor writes in a shape of its own, turned back into
  # the document's, one at a time; the first that cannot be is the refusal.
  defp convert(element, id) do
    [&options/1, &bounds/1, &step/1, &checks/1, &writes/1]
    |> Enum.reduce_while({:ok, element}, fn step, {:ok, acc} ->
      case step.(acc) do
        {:ok, acc} -> {:cont, {:ok, acc}}
        {:error, message} -> {:halt, {:error, [{id, message}]}}
      end
    end)
  end

  defp options(%{"answer_options" => rows} = element) do
    case ScreenEditor.ChoiceQuestion.answer_options(List.wrap(rows)) do
      {:ok, pairs} -> described(element, pairs)
      :error -> {:error, "each option is written value=Label"}
    end
  end

  defp options(%{"option_descriptions" => _rows} = element), do: described(element, [])
  defp options(element), do: {:ok, element}

  defp described(element, pairs) do
    {rows, element} = Map.pop(element, "option_descriptions", [])
    values = Enum.map(pairs, &elem(&1, 0))

    case ScreenEditor.ChoiceQuestion.option_descriptions(List.wrap(rows), values) do
      {:ok, descriptions} ->
        options =
          Enum.map(pairs, fn {value, label} ->
            put_present(%{"value" => value, "label" => label}, "description", descriptions[value])
          end)

        {:ok, put_present(element, "answer_options", options)}

      :error ->
        {:error, "each option description is written value=Description, naming an option once"}
    end
  end

  defp bounds(%{"type" => "text_question", "format" => format} = element)
       when format in @dated,
       do: {:ok, element}

  defp bounds(%{"type" => "text_question"} = element) do
    Enum.reduce_while(["min", "max"], {:ok, element}, fn field, {:ok, acc} ->
      case Map.fetch(acc, field) do
        {:ok, text} when is_binary(text) -> number(acc, field, text)
        _absent_or_number -> {:cont, {:ok, acc}}
      end
    end)
  end

  defp bounds(element), do: {:ok, element}

  defp step(%{"type" => "text_question", "step" => text} = element) when is_binary(text) do
    case number(element, "step", text) do
      {:cont, answer} -> answer
      {:halt, {:error, _bound}} -> {:error, "step is a number, or blank for no step"}
    end
  end

  defp step(element), do: {:ok, element}

  defp checks(%{"checks" => rows} = element) do
    case ScreenEditor.Element.checks(List.wrap(rows)) do
      {:ok, checks} -> {:ok, %{element | "checks" => checks}}
      :error -> {:error, "each check is written check.<name>: condition => message"}
    end
  end

  defp checks(element), do: {:ok, element}

  defp number(element, field, text) do
    case Integer.parse(text) do
      {integer, ""} ->
        {:cont, {:ok, %{element | field => integer}}}

      _not_an_integer ->
        case Float.parse(text) do
          {float, ""} -> {:cont, {:ok, %{element | field => float}}}
          _not_a_number -> {:halt, {:error, "#{field} is a number, or blank for no bound"}}
        end
    end
  end

  defp writes(%{"writes" => rows} = element) when is_list(rows) do
    rows
    |> Enum.reduce_while({:ok, %{}}, fn row, {:ok, acc} -> write(row, acc) end)
    |> case do
      {:ok, writes} -> {:ok, %{element | "writes" => writes}}
      {:error, message} -> {:error, message}
    end
  end

  defp writes(%{"writes" => _other}), do: {:error, "each write is written responses.<path>=value"}
  defp writes(element), do: {:ok, element}

  defp write(row, acc) do
    case split_write(row) do
      {:ok, path, _value} when is_map_key(acc, path) ->
        {:halt, {:error, "#{path} is written twice; each response path is written once"}}

      {:ok, path, value} ->
        {:cont, {:ok, Map.put(acc, path, ["const", value])}}

      :error ->
        {:halt, {:error, "each write is written responses.<path>=value"}}
    end
  end

  @doc """
  A button's write row, `responses.<path>=value`, as its path and constant,
  or `:error` when the row is not one.

  The value is read as JSON when it is JSON, and as the text itself when it
  is not, so a string that reads as JSON is written quoted.

      iex> StatifierExamples.ScreenEditor.Walk.split_write("responses.card=family")
      {:ok, "responses.card", "family"}

      iex> StatifierExamples.ScreenEditor.Walk.split_write("responses.guests=2")
      {:ok, "responses.guests", 2}

      iex> StatifierExamples.ScreenEditor.Walk.split_write(~s(responses.branch_code="12"))
      {:ok, "responses.branch_code", "12"}

      iex> StatifierExamples.ScreenEditor.Walk.split_write("card=family")
      :error
  """
  @spec split_write(term()) :: {:ok, String.t(), term()} | :error
  def split_write(row) when is_binary(row) do
    with [path, text] <- String.split(row, "=", parts: 2),
         true <- ScreenEditor.Button.response_path?(path) do
      {:ok, path, constant(text)}
    else
      _not_a_write -> :error
    end
  end

  def split_write(_row), do: :error

  defp constant(text) do
    case Jason.decode(text) do
      {:ok, value} -> value
      {:error, _not_json} -> text
    end
  end

  # Each item walked in order: the answers in order, and every refusal.
  defp collect(blocks, fun) do
    {answers, refusals} =
      Enum.reduce(blocks, {[], []}, fn block, {answers, refusals} ->
        case fun.(block) do
          {:ok, answer} -> {[answer | answers], refusals}
          {:error, more} -> {answers, Enum.reverse(more, refusals)}
        end
      end)

    {Enum.reverse(answers), Enum.reverse(refusals)}
  end

  defp modules, do: Map.new(ScreenEditor.registrations())
end
