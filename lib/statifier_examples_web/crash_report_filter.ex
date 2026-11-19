defmodule StatifierExamplesWeb.CrashReportFilter do
  @moduledoc """
  A Logger translator that keeps what a form posted out of a LiveView's
  crash report.

  A process that crashes is reported with the last message it received,
  and a LiveView's last message is the client event it was handling. Phoenix
  prints a `Phoenix.Socket.Message` with its payload's params filtered by
  `:phoenix, :filter_parameters` - which lists `"responses"`, the param
  every screen's form posts its answers under - but a form event's payload
  carries what the form posted as one encoded string,
  `responses%5Blibrary_pin%5D=...`, which no param filter reaches. A crash
  while a page handled the form's change event would print a typed PIN in
  that string.

  `translate/4` runs ahead of Elixir's own translator
  (`StatifierExamples.Application` adds it at start). For a GenServer's
  terminate report whose last message is a LiveView event carrying such a
  string, it decodes the string, filters the params it holds as Phoenix
  filters any other, and hands the report on to `Logger.Translator`, so
  the report prints as it always does with the posted values filtered. A
  string that does not decode is replaced whole with `"[FILTERED]"`: what
  cannot be read cannot be shown to be free of a secret. Every other
  report is left to the translators after this one.
  """

  alias Phoenix.Socket.Message
  alias Plug.Conn.Query

  @doc """
  The translator: a GenServer terminate report with its last message's
  posted form values filtered, or `:none` for any report this does not
  change.
  """
  @spec translate(Logger.level(), Logger.level(), atom(), term()) ::
          {:ok, iodata(), keyword()} | {:ok, iodata()} | :skip | :none
  def translate(
        min_level,
        level,
        :report,
        {:logger,
         %{label: {:gen_server, :terminate}, last_message: %Message{} = message} = report}
      ) do
    case filtered(message) do
      ^message ->
        :none

      filtered ->
        Logger.Translator.translate(
          min_level,
          level,
          :report,
          {:logger, %{report | last_message: filtered}}
        )
    end
  end

  def translate(_min_level, _level, _kind, _data), do: :none

  @spec filtered(Message.t()) :: Message.t()
  defp filtered(%Message{event: "event", payload: %{"value" => value} = payload} = message)
       when is_binary(value) do
    %{message | payload: %{payload | "value" => posted(value)}}
  end

  defp filtered(message), do: message

  # The posted string as the params it encodes, filtered.
  @spec posted(String.t()) :: map() | String.t()
  defp posted(value) do
    value |> Query.decode() |> Phoenix.Logger.filter_values()
  rescue
    Plug.Conn.InvalidQueryError -> "[FILTERED]"
  end
end
