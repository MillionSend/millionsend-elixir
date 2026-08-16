defmodule MillionSend.Contacts.Contact do
  @moduledoc "A contact. `remove/2` populates `contact` (its id) plus `deleted`."
  defstruct [
    :object,
    :id,
    :email,
    :first_name,
    :last_name,
    :created_at,
    :unsubscribed,
    :properties,
    :deleted,
    :contact
  ]
end

defmodule MillionSend.Contacts do
  @moduledoc """
  Contacts, addressable by id **or** email — email wins when both are given.
  Pass `:audience_id` to scope a call to an audience; omit it for the top-level
  contact routes.

      MillionSend.Contacts.create(%{audience_id: aud, email: "ada@acme.dev", first_name: "Ada"})
      MillionSend.Contacts.get(%{audience_id: aud, email: "ada@acme.dev"})
      MillionSend.Contacts.get("contact-uuid")
      MillionSend.Contacts.update(%{id: id, unsubscribed: true, first_name: nil}) # nil clears
  """

  alias MillionSend.{Client, Request}
  alias MillionSend.Contacts.Contact

  @create_fields [:email, :first_name, :last_name, :unsubscribed, :properties]
  @update_fields [:first_name, :last_name, :unsubscribed, :properties]

  @type address :: String.t() | map()

  @doc "`POST /audiences/:audience_id/contacts` (or `/contacts`)."
  @spec create(Client.t(), map()) :: {:ok, Contact.t()} | {:error, MillionSend.Error.t()}
  def create(client \\ MillionSend.client(), params) when is_map(params) do
    Request.run(client,
      method: :post,
      path: collection_path(params),
      body: Request.take(params, @create_fields),
      as: Contact
    )
  end

  @doc "`GET` a contact by id/email map or a bare id string."
  @spec get(Client.t(), address()) :: {:ok, Contact.t()} | {:error, MillionSend.Error.t()}
  def get(client \\ MillionSend.client(), address) do
    Request.run(client, method: :get, path: member_path(address), as: Contact)
  end

  @doc "`PATCH` a contact. Include a key with `nil` to clear it; omit to leave unchanged."
  @spec update(Client.t(), map()) :: {:ok, Contact.t()} | {:error, MillionSend.Error.t()}
  def update(client \\ MillionSend.client(), params) when is_map(params) do
    Request.run(client,
      method: :patch,
      path: member_path(params),
      body: Request.take(params, @update_fields),
      as: Contact
    )
  end

  @doc "`DELETE` a contact by id/email map or a bare id string."
  @spec remove(Client.t(), address()) :: {:ok, Contact.t()} | {:error, MillionSend.Error.t()}
  def remove(client \\ MillionSend.client(), address) do
    Request.run(client, method: :delete, path: member_path(address), as: Contact)
  end

  @doc "`GET` contacts. Accepts `audience_id:`, `limit:`, `after:`, `before:`."
  @spec list(Client.t() | keyword()) ::
          {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(), do: list(MillionSend.client(), [])
  def list(%Client{} = client), do: list(client, [])
  def list(opts) when is_list(opts), do: list(MillionSend.client(), opts)

  @spec list(Client.t(), keyword()) ::
          {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(%Client{} = client, opts) when is_list(opts) do
    Request.run(client,
      method: :get,
      path: collection_path(Map.new(opts)),
      query: Request.list_query(opts),
      as: {:list, Contact}
    )
  end

  @doc """
  `PATCH /contacts/:id_or_email/topics` — set per-topic subscriptions (always a
  top-level route). `params` carries the address plus `topics:` as a list of
  `%{id: ..., subscription: :opt_in | :opt_out}`.
  """
  @spec update_topics(Client.t(), map()) :: {:ok, Contact.t()} | {:error, MillionSend.Error.t()}
  def update_topics(client \\ MillionSend.client(), params) when is_map(params) do
    topics = Map.get(params, :topics) || Map.get(params, "topics") || []

    Request.run(client,
      method: :patch,
      path: "/contacts/" <> member_key(params) <> "/topics",
      body: topics,
      as: Contact
    )
  end

  defp collection_path(map) do
    case Map.get(map, :audience_id) || Map.get(map, "audience_id") do
      nil -> "/contacts"
      audience_id -> "/audiences/" <> Request.encode(audience_id) <> "/contacts"
    end
  end

  defp member_path(address) do
    map = normalize(address)
    collection_path(map) <> "/" <> member_key(map)
  end

  # Email wins over id when both are present.
  defp member_key(map) do
    key = Map.get(map, :email) || Map.get(map, "email") || Map.get(map, :id) || Map.get(map, "id")
    Request.encode(key || "")
  end

  defp normalize(address) when is_binary(address), do: %{id: address}
  defp normalize(address) when is_map(address), do: address
end
