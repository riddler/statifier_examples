defmodule StatifierExamples.DeskTransport do
  @moduledoc """
  The test transport for `StatifierExamples.HoldDesk`'s outbound
  BasicHTTP POSTs: it sends `{:desk_post, url, headers, body}` to the
  process performing the POST, which is the test process that routed the
  hold request, and answers the status the process put under
  `:desk_status`, 204 as a branch desk would when it put none.
  """

  @behaviour Statifier.Send.BasicHTTP.Transport

  @impl true
  def post(url, headers, body) do
    send(self(), {:desk_post, url, headers, body})
    {:ok, Process.get(:desk_status, 204)}
  end
end
