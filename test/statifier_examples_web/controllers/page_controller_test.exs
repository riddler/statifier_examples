defmodule StatifierExamplesWeb.PageControllerTest do
  use StatifierExamplesWeb.ConnCase

  # Sabotage: renamed the "Documents" heading in home.html.heex; this test
  # went red, then reverted.
  test "GET / renders the documents index", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Documents"
  end
end
