defmodule MillionSend.Contacts.Contact do
  @moduledoc """
  A contact. `remove/2` populates `contact` (its id) plus `deleted`.
  `properties` is a map of `key => %{"type" => "string" | "number", "value" => ...}`.
  """
  @type t :: %__MODULE__{}
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

defmodule MillionSend.Contacts.TopicSubscription do
  @moduledoc """
  A contact's effective subscription to one topic, as returned by
  `MillionSend.Contacts.list_topics/2`. `subscription` is `"opt_in"` or
  `"opt_out"`; `explicit` is `false` when that is the topic's default rather
  than the contact's own choice; `visibility` is `"public"` or `"private"` (the
  hosted preference page lists public topics only).
  """
  @type t :: %__MODULE__{}
  defstruct [:id, :name, :description, :subscription, :explicit, :visibility]
end

defmodule MillionSend.Contacts.PreferencesLink do
  @moduledoc """
  A contact's hosted preference-page URL, as returned by
  `MillionSend.Contacts.preferences_link/2`. `contact` is the contact id. The
  link is a signed, contact-scoped capability with no expiry: anyone holding it
  can change that contact's preferences, so hand it only to the contact.
  """
  @type t :: %__MODULE__{}
  defstruct [:object, :contact, :url]
end

defmodule MillionSend.Contacts.BatchResponse do
  @moduledoc """
  The result of `MillionSend.Contacts.create_batch/3`: one `Item` per
  successful request item (in request order), per-status `counts`
  (`created`/`updated`/`skipped`/`failed`, summing to the request length) and,
  in permissive mode, the failed items as `errors`.
  """

  defmodule Item do
    @moduledoc "An accepted batch item: its request `index`, the contact `id` and `status` (`\"created\" | \"updated\" | \"skipped\"`)."
    @type t :: %__MODULE__{}
    defstruct [:object, :index, :id, :status]
  end

  alias MillionSend.{BatchError, Request}

  @type t :: %__MODULE__{data: [Item.t()], counts: map(), errors: [BatchError.t()]}
  defstruct data: [], counts: %{created: 0, updated: 0, skipped: 0, failed: 0}, errors: []

  @doc false
  def cast(map) do
    counts = map["counts"] || %{}

    %__MODULE__{
      data: Enum.map(map["data"] || [], &Request.cast_struct(Item, &1)),
      counts: Map.new([:created, :updated, :skipped, :failed], &{&1, counts[to_string(&1)] || 0}),
      errors: BatchError.cast_list(map["errors"])
    }
  end
end

defmodule MillionSend.Contacts do
  @moduledoc """
  Contacts are team-global (one per email per team, case-insensitive) and
  addressable by id **or** email — email wins when both are given.

  Input maps are sent as given: `create/2` accepts `email`, `first_name`,
  `last_name`, `unsubscribed`, `properties`, `segments` (`[%{id: ...}]`) and
  `topics` (`[%{id: ..., subscription: ...}]`); `update/2` accepts `first_name`,
  `last_name`, `unsubscribed` and `properties`, where `nil` clears a field.

      MillionSend.Contacts.create(%{email: "ada@acme.dev", first_name: "Ada"})
      MillionSend.Contacts.get(%{email: "ada@acme.dev"})
      MillionSend.Contacts.get("contact-uuid")
      MillionSend.Contacts.update(%{id: id, unsubscribed: true, first_name: nil}) # nil clears
      MillionSend.Contacts.batch_remove(%{emails: ["ada@acme.dev"]})
      MillionSend.Contacts.preferences_link(%{email: "ada@acme.dev"})
  """

  alias MillionSend.{Client, Request}
  alias MillionSend.Contacts.{BatchResponse, Contact, PreferencesLink, TopicSubscription}

  @type address :: String.t() | map()

  # The address keys `update/2` reads from `params`; they are not body fields.
  @address_keys [:id, :email, "id", "email"]

  @doc """
  `POST /contacts`. A duplicate email (per team, case-insensitive) is a 409
  `validation_error`.
  """
  @spec create(Client.t(), map()) :: {:ok, Contact.t()} | {:error, MillionSend.Error.t()}
  def create(client \\ MillionSend.client(), params) when is_map(params) do
    Request.run(client, method: :post, path: "/contacts", body: params, as: Contact)
  end

  @doc """
  `POST /contacts/batch` — 1..1000 `create/2` payloads in one call. Options:
  `on_conflict:` (`:error`, the default, `:skip` or `:upsert`; sent as the query
  parameter) and `batch_validation:` (`:strict`, the default, or `:permissive`;
  sent as the `x-batch-validation` header). Returns a
  `MillionSend.Contacts.BatchResponse`; only permissive mode fills `errors`.
  """
  @spec create_batch([map()]) :: {:ok, BatchResponse.t()} | {:error, MillionSend.Error.t()}
  def create_batch(list) when is_list(list), do: create_batch(MillionSend.client(), list, [])

  @spec create_batch(Client.t() | [map()], [map()] | keyword()) ::
          {:ok, BatchResponse.t()} | {:error, MillionSend.Error.t()}
  def create_batch(%Client{} = client, list) when is_list(list),
    do: create_batch(client, list, [])

  def create_batch(list, opts) when is_list(list) and is_list(opts),
    do: create_batch(MillionSend.client(), list, opts)

  @spec create_batch(Client.t(), [map()], keyword()) ::
          {:ok, BatchResponse.t()} | {:error, MillionSend.Error.t()}
  def create_batch(%Client{} = client, list, opts) when is_list(list) and is_list(opts) do
    Request.run(client,
      method: :post,
      path: "/contacts/batch",
      query: [on_conflict: opts[:on_conflict]],
      body: list,
      batch_validation: opts[:batch_validation],
      as: &BatchResponse.cast/1
    )
  end

  @doc """
  `POST /contacts/batch/remove` — delete by `%{emails: [...]}` or `%{ids: [...]}`
  (up to 1000). Returns only the contacts actually deleted, each with `contact`
  (its id) and `deleted: true`; unknown ids or addresses are skipped.
  """
  @spec batch_remove(Client.t(), map()) :: {:ok, [Contact.t()]} | {:error, MillionSend.Error.t()}
  def batch_remove(client \\ MillionSend.client(), params) when is_map(params) do
    Request.run(client,
      method: :post,
      path: "/contacts/batch/remove",
      body: params,
      as: {:data, Contact}
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
      body: Map.drop(params, @address_keys),
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
  `GET /contacts/:id_or_email/topics` — every topic with the contact's effective
  `subscription` (`"opt_in" | "opt_out"`) and whether it is `explicit` or the
  topic's default. Returns a `MillionSend.List` of `TopicSubscription`s.
  """
  @spec list_topics(Client.t(), address()) ::
          {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list_topics(client \\ MillionSend.client(), address) do
    Request.run(client,
      method: :get,
      path: member_path(address) <> "/topics",
      as: {:list, TopicSubscription}
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

  @doc """
  `POST /contacts/:id_or_email/preferences-link` — the contact's hosted
  preferences URL (the page their unsubscribe links open), for deep-linking from
  a settings screen. A 422 `validation_error` when the instance cannot mint
  hosted links; `not_found` for an unknown contact.
  """
  @spec preferences_link(Client.t(), address()) ::
          {:ok, PreferencesLink.t()} | {:error, MillionSend.Error.t()}
  def preferences_link(client \\ MillionSend.client(), address) do
    Request.run(client,
      method: :post,
      path: member_path(address) <> "/preferences-link",
      as: PreferencesLink
    )
  end

  @doc "`POST /contacts/:id_or_email/segments/:segment_id` — add the contact to a segment."
  @spec add_to_segment(Client.t(), address(), String.t()) ::
          {:ok, Contact.t()} | {:error, MillionSend.Error.t()}
  def add_to_segment(client \\ MillionSend.client(), address, segment_id)
      when is_binary(segment_id) do
    Request.run(client, method: :post, path: segment_path(address, segment_id), as: Contact)
  end

  @doc "`DELETE /contacts/:id_or_email/segments/:segment_id` — remove the contact from a segment."
  @spec remove_from_segment(Client.t(), address(), String.t()) ::
          {:ok, Contact.t()} | {:error, MillionSend.Error.t()}
  def remove_from_segment(client \\ MillionSend.client(), address, segment_id)
      when is_binary(segment_id) do
    Request.run(client, method: :delete, path: segment_path(address, segment_id), as: Contact)
  end

  defp segment_path(address, segment_id),
    do: member_path(address) <> "/segments/" <> Request.encode(segment_id)

  defp member_path(address), do: "/contacts/" <> member_key(normalize(address))

  # Email wins over id when both are present.
  defp member_key(map) do
    key = Map.get(map, :email) || Map.get(map, "email") || Map.get(map, :id) || Map.get(map, "id")
    Request.encode(key || "")
  end

  defp normalize(address) when is_binary(address), do: %{id: address}
  defp normalize(address) when is_map(address), do: address
end
