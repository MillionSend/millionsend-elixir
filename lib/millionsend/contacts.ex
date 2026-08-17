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
  Contacts are team-global (one per email per team, case-insensitive) and
  addressable by id **or** email — email wins when both are given.

      MillionSend.Contacts.create(%{email: "ada@acme.dev", first_name: "Ada"})
      MillionSend.Contacts.get(%{email: "ada@acme.dev"})
      MillionSend.Contacts.get("contact-uuid")
      MillionSend.Contacts.update(%{id: id, unsubscribed: true, first_name: nil}) # nil clears
  """

  alias MillionSend.{Client, Request}
  alias MillionSend.Contacts.Contact

  @create_fields [:email, :first_name, :last_name, :unsubscribed, :properties]
  @update_fields [:first_name, :last_name, :unsubscribed, :properties]

  @type address :: String.t() | map()

  @doc """
  `POST /contacts`. A duplicate email (per team, case-insensitive) is a 409
  `validation_error`.
  """
  @spec create(Client.t(), map()) :: {:ok, Contact.t()} | {:error, MillionSend.Error.t()}
  def create(client \\ MillionSend.client(), params) when is_map(params) do
    Request.run(client,
      method: :post,
      path: "/contacts",
      body: Request.take(params, @create_fields),
      as: Contact
    )
  end

  @doc "`GET /contacts/:id_or_email` — by id/email map or a bare id string."
  @spec get(Client.t(), address()) :: {:ok, Contact.t()} | {:error, MillionSend.Error.t()}
  def get(client \\ MillionSend.client(), address) do
    Request.run(client, method: :get, path: member_path(address), as: Contact)
  end

  @doc "`PATCH /contacts/:id_or_email`. Include a key with `nil` to clear it; omit to leave unchanged."
  @spec update(Client.t(), map()) :: {:ok, Contact.t()} | {:error, MillionSend.Error.t()}
  def update(client \\ MillionSend.client(), params) when is_map(params) do
    Request.run(client,
      method: :patch,
      path: member_path(params),
      body: Request.take(params, @update_fields),
      as: Contact
    )
  end

  @doc "`DELETE /contacts/:id_or_email` — by id/email map or a bare id string."
  @spec remove(Client.t(), address()) :: {:ok, Contact.t()} | {:error, MillionSend.Error.t()}
  def remove(client \\ MillionSend.client(), address) do
    Request.run(client, method: :delete, path: member_path(address), as: Contact)
  end

  @doc "`GET /contacts` — accepts `limit:`, `after:`, `before:`."
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
      path: "/contacts",
      query: Request.list_query(opts),
      as: {:list, Contact}
    )
  end

  @doc """
  `PATCH /contacts/:id_or_email/topics` — set per-topic subscriptions. `params`
  carries the address plus `topics:` as a list of
  `%{id: ..., subscription: :opt_in | :opt_out}`.
  """
  @spec update_topics(Client.t(), map()) :: {:ok, Contact.t()} | {:error, MillionSend.Error.t()}
  def update_topics(client \\ MillionSend.client(), params) when is_map(params) do
    topics = Map.get(params, :topics) || Map.get(params, "topics") || []

    Request.run(client,
      method: :patch,
      path: member_path(params) <> "/topics",
      body: topics,
      as: Contact
    )
  end

  defp member_path(address), do: "/contacts/" <> member_key(normalize(address))

  # Email wins over id when both are present.
  defp member_key(map) do
    key = Map.get(map, :email) || Map.get(map, "email") || Map.get(map, :id) || Map.get(map, "id")
    Request.encode(key || "")
  end

  defp normalize(address) when is_binary(address), do: %{id: address}
  defp normalize(address) when is_map(address), do: address
end
