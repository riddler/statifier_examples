defmodule StatifierExamplesWeb.SignupElementsTest do
  @moduledoc """
  The screen editor's Try renderer draws the display elements an author
  can place from the palette - an image, a divider and a link - rather
  than raising on them as types it does not know.
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias StatifierExamplesWeb.SignupElements

  # Sabotage: made element/1 draw an image as the divider; the img
  # assertion went red, then reverted from a copy.
  test "draws an image, a divider and a link as plain HTML" do
    nodes = [
      %{"type" => "image", "key" => "logo", "src" => "/images/logo.svg", "alt" => "Riverbend"},
      %{"type" => "divider", "key" => "rule"},
      %{
        "type" => "link",
        "key" => "rules",
        "label" => "Lending rules",
        "href" => "/lending-rules"
      }
    ]

    html = render_component(&SignupElements.screen/1, title: "Your details", nodes: nodes)

    assert html =~ ~r{<img[^>]* id="logo" src="/images/logo.svg" alt="Riverbend"}
    assert html =~ ~r{<hr[^>]* id="rule"}
    assert html =~ ~r{<a[^>]* id="rules" href="/lending-rules"[^>]*>\s*Lending rules\s*</a>}
  end
end
