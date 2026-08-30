defmodule StatifierExamplesWeb.PageControllerTest do
  use StatifierExamplesWeb.ConnCase

  alias StatifierExamples.Charts

  # Sabotage: renamed the "Documents" heading in home.html.heex; this test
  # went red, then reverted.
  test "GET / renders the documents index", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Documents"
  end

  # The index is the only page that names every fixture, so it is asserted
  # against Charts.fixtures/0 rather than against three names typed here: a
  # fourth example document that never reaches the index is the failure this
  # catches, and a hard-coded list would not.
  #
  # Sabotage: dropped the :for over @fixtures from home.html.heex; this went
  # red, then reverted.
  test "GET / lists every fixture with a link into the editor", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    for fixture <- Charts.fixtures() do
      assert html =~ fixture.name
      assert html =~ ~s(href="/editor?doc=#{fixture.key}")
      assert html =~ "revision #{fixture.document.revision}"
    end
  end
end
