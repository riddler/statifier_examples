defmodule StatifierExamples.Signup.Sealer do
  @moduledoc """
  The app's sealer: the function `StatifierExamples.Signup.Journey.submit/4`
  hands `Riddler.Screens.seal_secrets/4`, which turns the text a patron typed
  into a secret question - the PIN for their library card - into the opaque
  string the execution keeps instead.

  `seal/1` is that function. riddler takes the sealer as an argument and
  stores nothing of it, so which sealer runs is this app's choice, made
  here:

    * **By default** the text is encrypted with `Plug.Crypto.encrypt/4`
      under the endpoint's `secret_key_base`. That is the key this app
      already holds for its sessions, and `plug_crypto` is already in the
      lock through Phoenix, so sealing costs no new dependency and no new
      secret. Only a holder of the same
      `secret_key_base` opens a sealed string again, with
      `Plug.Crypto.decrypt/4` under the same salt.
    * **Under `config/test.exs`** the application environment names a
      module as `:sealer`, and `seal/1` calls that module's `seal/1`
      instead. The suite's sealer is deterministic, so a test can say which
      sealed string a response became without decrypting anything.

  Either way the answer is `{:ok, sealed}` with `sealed` a string, or
  `{:error, reason}`, the two shapes riddler reads; riddler refuses any
  other answer as `response.seal_failed` and seals nothing.
  """

  # Names what the encryption is for, so a string sealed here is not one a
  # session cookie's decryption accepts, or the other way round.
  @salt "library card secret"

  @doc """
  Seals `plaintext` with the configured sealer, or the endpoint's when no
  sealer is configured.
  """
  @spec seal(String.t()) :: {:ok, String.t()} | {:error, term()}
  def seal(plaintext) when is_binary(plaintext) do
    case configured() do
      nil -> endpoint_seal(plaintext)
      sealer -> sealer.seal(plaintext)
    end
  end

  # Encrypts the text under the endpoint's secret_key_base. Plug.Crypto
  # writes an age into the token; whoever opens a sealed PIN again passes
  # `max_age: :infinity` to `Plug.Crypto.decrypt/4`, because a PIN is kept as
  # long as the card it belongs to.
  @spec endpoint_seal(String.t()) :: {:ok, String.t()}
  defp endpoint_seal(plaintext) do
    {:ok, Plug.Crypto.encrypt(secret_key_base(), @salt, plaintext)}
  end

  @spec configured() :: module() | nil
  defp configured do
    :statifier_examples
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:sealer)
  end

  @spec secret_key_base() :: String.t()
  defp secret_key_base,
    do: StatifierExamplesWeb.Endpoint.config(:secret_key_base)
end
