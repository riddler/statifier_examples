defmodule StatifierExamples.DeskTransport do
  @moduledoc """
  The test transport for `StatifierExamples.HoldDesk`'s outbound
  BasicHTTP POSTs: it sends `{:desk_post, url, headers, body}` to the
  process performing the POST, which is the test process that drained the
  desk's job queue, and answers the status the process put under
  `:desk_status`, 204 as a branch desk would when it put none.

  A test that needs to see the moment the desk is called puts a
  zero-arity function under `:desk_answering`; it is called first, while
  the desk is still answering.
  """

  @behaviour Statifier.Send.BasicHTTP.Transport

  @impl true
  def post(url, headers, body) do
    if answering = Process.get(:desk_answering), do: answering.()
    send(self(), {:desk_post, url, headers, body})
    {:ok, Process.get(:desk_status, 204)}
  end
end
