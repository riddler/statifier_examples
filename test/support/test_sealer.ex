defmodule StatifierExamples.TestSealer do
  @moduledoc """
  The suite's sealer, which `config/test.exs` names as the `:sealer` of
  `StatifierExamples.Signup.Sealer`.

  It is deterministic - one text always seals to one string - so a test can
  say which sealed string a response became, and what it answers holds
  nothing of the text it sealed: a fixed prefix and the first sixteen hex
  digits of the text's SHA-256.
  """

  @doc """
  Seals `plaintext` to `"test-sealed:"` and a digest of it.
  """
  @spec seal(String.t()) :: {:ok, String.t()}
  def seal(plaintext) when is_binary(plaintext), do: {:ok, sealed(plaintext)}

  @doc """
  The string `seal/1` answers for `plaintext`.
  """
  @spec sealed(String.t()) :: String.t()
  def sealed(plaintext) when is_binary(plaintext) do
    digest = :sha256 |> :crypto.hash(plaintext) |> Base.encode16(case: :lower)
    "test-sealed:" <> binary_part(digest, 0, 16)
  end
end
