defmodule StatifierExamples.FormPost.CardApplication do
  @moduledoc """
  One application posted on the Riverbend Public Library's card
  application form: the `card_applications` table's schema.

  The table is the host's, and it is the only place the posted values are
  kept. What the visitor typed - a name, an email address, a phone number,
  a street address, and whether they want a library card, the events
  newsletter or both - is cast by `changeset/2`; the library system
  (`scope`), the `status` and the outside system's `external_reference`
  are the host's to set and never come from the form.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          scope: String.t() | nil,
          name: String.t() | nil,
          email: String.t() | nil,
          phone: String.t() | nil,
          street_address: String.t() | nil,
          wants_card: boolean() | nil,
          wants_newsletter: boolean() | nil,
          idempotency_key: String.t() | nil,
          status: String.t() | nil,
          external_reference: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "card_applications" do
    field(:scope, :string)
    field(:name, :string)
    field(:email, :string)
    field(:phone, :string)
    field(:street_address, :string)
    field(:wants_card, :boolean, default: false)
    field(:wants_newsletter, :boolean, default: false)
    field(:idempotency_key, :string)
    field(:status, :string, default: "received")
    field(:external_reference, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @form_fields [
    :name,
    :email,
    :phone,
    :street_address,
    :wants_card,
    :wants_newsletter,
    :idempotency_key
  ]

  @doc """
  The changeset for the fields a visitor posts.

  A name, an email address, a street address and the client's
  idempotency key are required, and at least one of the two interests: an
  application that asks for neither a card nor the newsletter has nothing
  for the library to do. The unique constraint names the `(scope,
  idempotency_key)` index, so a second writer that inserts without
  `StatifierExamples.FormPost.CardApplications`' upsert gets a changeset
  error rather than a raised `Exqlite.Error`.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(application, attrs) do
    application
    |> cast(attrs, @form_fields)
    |> validate_required([:name, :email, :street_address, :idempotency_key])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/, message: "must be an email address")
    |> validate_length(:idempotency_key, max: 255)
    |> validate_interest()
    |> unique_constraint([:scope, :idempotency_key])
  end

  @spec validate_interest(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_interest(changeset) do
    if get_field(changeset, :wants_card) or get_field(changeset, :wants_newsletter) do
      changeset
    else
      add_error(changeset, :wants_card, "choose a library card, the newsletter, or both")
    end
  end
end
