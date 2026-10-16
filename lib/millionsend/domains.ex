defmodule MillionSend.Domains.Domain.Record do
  @moduledoc """
  One DNS record to publish for a domain: `record` (the role, e.g. SPF, DKIM,
  DMARC or Tracking), `name`, `type`, `ttl`, `value`, `status` and, for MX,
  `priority`.
  """
  @type t :: %__MODULE__{}
  defstruct [:record, :name, :type, :ttl, :status, :value, :priority]
end

defmodule MillionSend.Domains.Domain do
  @moduledoc """
  A sending domain. `records` lists the DNS records to publish (empty on list
  and delete responses); `capabilities` is the `%{"sending" => ..., "receiving"
  => ...}` map as returned by the API. `receiving_catch_all`: on, mail to
  addresses without an inbox lands in the received list; off, those addresses
  are refused at SMTP time.

  `shared` is `true` on the team's subdomain of the shared inbox domain and
  `false` on the team's own domains (older servers don't send it, which reads
  as `false`). Only that shared row carries `sending_mode` (`"open"`,
  `"reply_only"` or `"receive_only"`: what its inboxes' addresses may send) and
  `sending_mode_reason` (`"plan"` or `"instance"`: what holds sending below
  `"open"`; `nil` under `"open"`). Both are plain strings: the API may add
  values.
  """
  alias MillionSend.Domains.Domain.Record
  alias MillionSend.Request

  @type t :: %__MODULE__{}
  defstruct [
    :object,
    :id,
    :name,
    :status,
    :created_at,
    :region,
    :open_tracking,
    :click_tracking,
    :tracking_subdomain,
    :capabilities,
    :receiving_catch_all,
    :sending_mode,
    :sending_mode_reason,
    :deleted,
    shared: false,
    records: []
  ]

  @doc false
  def cast(map) do
    domain = Request.cast_struct(__MODULE__, map)
    %{domain | records: Enum.map(domain.records || [], &Request.cast_struct(Record, &1))}
  end
end

defmodule MillionSend.Domains do
  @moduledoc """
  Sending domains: add one, publish the returned DNS `records`, then `verify/2`.

  Input maps are sent as given: `create/2` accepts `name`, `region`,
  `custom_return_path`, `open_tracking`, `click_tracking` and
  `tracking_subdomain`; `update/3` accepts `open_tracking`, `click_tracking`,
  `tracking_subdomain` (`nil` clears it) and `receiving_catch_all` (a paid plan
  on MillionSend Cloud).

      {:ok, domain} = MillionSend.Domains.create(%{name: "acme.dev"})
      domain.records  # [%MillionSend.Domains.Domain.Record{record: "DKIM", ...}, ...]

  On an instance with a shared inbox domain, the team's subdomain of it is
  listed too (MillionSend v0.14.0 and later), as the last row and with
  `shared: true`. It is verified, has no DNS records, and its id is the
  `domain_id` of the team's shared inboxes. It is read-only: `update/3`,
  `verify/2` and `remove/2` answer 403 `"forbidden"`. It sends only from its
  inboxes' own addresses, so leave it out when picking a domain to send from:

      {:ok, %{data: domains}} = MillionSend.Domains.list(limit: 100)
      sender = Enum.find(domains, &(&1.status == "verified" and not &1.shared))
  """

  alias MillionSend.{Client, Request}
  alias MillionSend.Domains.Domain

  @doc "`POST /domains`"
  @spec create(Client.t(), map()) :: {:ok, Domain.t()} | {:error, MillionSend.Error.t()}
  def create(client \\ MillionSend.client(), params) when is_map(params) do
    Request.run(client, method: :post, path: "/domains", body: params, as: &Domain.cast/1)
  end

  @doc "`GET /domains/:id`"
  @spec get(Client.t(), String.t()) :: {:ok, Domain.t()} | {:error, MillionSend.Error.t()}
  def get(client \\ MillionSend.client(), id) when is_binary(id) do
    Request.run(client, method: :get, path: member_path(id), as: &Domain.cast/1)
  end

  @doc """
  `GET /domains` — the team's own domains newest first, then the shared row,
  whatever its `created_at` (alone on the next page when the own domains
  exactly fill one). Accepts `limit:`, `after:`, `before:`.
  """
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
      path: "/domains",
      query: Request.list_query(opts),
      as: {:list, Domain}
    )
  end

  @doc "`POST /domains/:id/verify` — re-check the DNS records."
  @spec verify(Client.t(), String.t()) :: {:ok, Domain.t()} | {:error, MillionSend.Error.t()}
  def verify(client \\ MillionSend.client(), id) when is_binary(id) do
    Request.run(client, method: :post, path: member_path(id) <> "/verify", as: &Domain.cast/1)
  end

  @doc """
  `PATCH /domains/:id` — tracking settings; `tracking_subdomain: nil` clears it.
  The shared row answers 403 `"forbidden"`, here and on `verify/2` and `remove/2`.
  """
  @spec update(Client.t(), String.t(), map()) ::
          {:ok, Domain.t()} | {:error, MillionSend.Error.t()}
  def update(client \\ MillionSend.client(), id, params) when is_binary(id) and is_map(params) do
    Request.run(client, method: :patch, path: member_path(id), body: params, as: &Domain.cast/1)
  end

  @doc "`DELETE /domains/:id`"
  @spec remove(Client.t(), String.t()) :: {:ok, Domain.t()} | {:error, MillionSend.Error.t()}
  def remove(client \\ MillionSend.client(), id) when is_binary(id) do
    Request.run(client, method: :delete, path: member_path(id), as: &Domain.cast/1)
  end

  defp member_path(id), do: "/domains/" <> Request.encode(id)
end
