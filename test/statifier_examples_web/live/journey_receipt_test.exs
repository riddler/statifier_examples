defmodule StatifierExamplesWeb.JourneyReceiptTest do
  @moduledoc """
  What the Journey page draws of a done execution's receipt: the fields it
  names, and nothing else the receipt carries.
  """

  use ExUnit.Case, async: true

  alias StatifierExamplesWeb.SignupJourneyLive

  doctest SignupJourneyLive

  # Sabotage (run): made `receipt/1` answer every field the receipt
  # carries, as an inspect of the whole receipt drew it. The field no list
  # names was drawn and this went red. Restored from a copy.
  test "a field the receipt carries and the page does not name is not drawn" do
    result = %{
      "created" => %{
        "created" => true,
        "email" => "rosa@example.com",
        "collected" => 3,
        "added_later" => "not reviewed"
      }
    }

    assert SignupJourneyLive.receipt(result) == [
             {"Account for", "rosa@example.com"},
             {"Responses collected", "3"}
           ]
  end
end
