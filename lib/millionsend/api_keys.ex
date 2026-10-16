defmodule MillionSend.ApiKeys.ApiKey do
  @moduledoc """
  An API key. `token` is returned only by `create/2` — store it, it cannot be
  fetched again. `inbox_id` is set for a key restricted to one inbox.
  `remove/2` populates `id` plus `deleted`.
  """
  @type t :: %__MODULE__{}
  defstruct [:object, :id, :name, :token, :created_at, :last_used_at, :inbox_id, :deleted]
end

defmodule MillionSend.ApiKeys do
  @moduledoc """
  API keys. Input maps are sent as given: `name`, `permission`
  (`:full_access`, the default, or `:sending_access`), `domain_id`
  (restrict a sending key to one of the team's own domains; the `shared: true`
  row of `MillionSend.Domains.list/2` answers 422 `"validation_error"`) and
  `inbox_id` (restrict a full-access key to one inbox: it reads that inbox and
  sends from its address only).

      {:ok, key} = MillionSend.ApiKeys.create(%{name: "ci", permission: :sending_access})
      key.token
  """

  alias MillionSend.{Client, Request}
  alias MillionSend.ApiKeys.ApiKey

  @doc "`POST /api-keys` — the response carries the one-time `token`."
  @spec create(Client.t(), map()) :: {:ok, ApiKey.t()} | {:error, MillionSend.Error.t()}
  def create(client \\ MillionSend.client(), params) when is_map(params) do
    Request.run(client, method: :post, path: "/api-keys", body: params, as: ApiKey)
  end

  @doc "`GET /api-keys` — accepts `limit:`, `after:`, `before:`."
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
      path: "/api-keys",
      query: Request.list_query(opts),
      as: {:list, ApiKey}
    )
  end

  @doc "`DELETE /api-keys/:id`"
  @spec remove(Client.t(), String.t()) :: {:ok, ApiKey.t()} | {:error, MillionSend.Error.t()}
  def remove(client \\ MillionSend.client(), id) when is_binary(id) do
    Request.run(client, method: :delete, path: "/api-keys/" <> Request.encode(id), as: ApiKey)
  end
end
