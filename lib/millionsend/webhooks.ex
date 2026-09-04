defmodule MillionSend.Webhooks.Webhook do
  @moduledoc """
  A webhook endpoint. `signing_secret` is returned by `create/2` and `get/2`;
  `status` is `"enabled" | "disabled"`. `remove/2` populates `id` plus `deleted`.
  """
  @type t :: %__MODULE__{}
  defstruct [:object, :id, :endpoint, :events, :status, :signing_secret, :created_at, :deleted]
end

defmodule MillionSend.Webhooks do
  @moduledoc """
  Webhooks. Input maps are sent as given: `create/2` accepts `endpoint`,
  `events` and an optional `signing_secret` (carry over an existing `whsec_`
  secret so the receiver keeps verifying unchanged); `update/3` accepts
  `endpoint`, `events` and `status`.

      MillionSend.Webhooks.create(%{
        endpoint: "https://acme.dev/hooks/email",
        events: ["email.delivered", "email.bounced"]
      })
  """

  alias MillionSend.{Client, Request}
  alias MillionSend.Webhooks.Webhook

  @doc "`POST /webhooks` — the response carries the `signing_secret`."
  @spec create(Client.t(), map()) :: {:ok, Webhook.t()} | {:error, MillionSend.Error.t()}
  def create(client \\ MillionSend.client(), params) when is_map(params) do
    Request.run(client, method: :post, path: "/webhooks", body: params, as: Webhook)
  end

  @doc "`GET /webhooks/:id` — includes the `signing_secret`."
  @spec get(Client.t(), String.t()) :: {:ok, Webhook.t()} | {:error, MillionSend.Error.t()}
  def get(client \\ MillionSend.client(), id) when is_binary(id) do
    Request.run(client, method: :get, path: member_path(id), as: Webhook)
  end

  @doc "`GET /webhooks` — accepts `limit:`, `after:`, `before:`."
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
      path: "/webhooks",
      query: Request.list_query(opts),
      as: {:list, Webhook}
    )
  end

  @doc "`PATCH /webhooks/:id` — `endpoint`, `events`, `status` (`:enabled | :disabled`)."
  @spec update(Client.t(), String.t(), map()) ::
          {:ok, Webhook.t()} | {:error, MillionSend.Error.t()}
  def update(client \\ MillionSend.client(), id, params) when is_binary(id) and is_map(params) do
    Request.run(client, method: :patch, path: member_path(id), body: params, as: Webhook)
  end

  @doc "`DELETE /webhooks/:id`"
  @spec remove(Client.t(), String.t()) :: {:ok, Webhook.t()} | {:error, MillionSend.Error.t()}
  def remove(client \\ MillionSend.client(), id) when is_binary(id) do
    Request.run(client, method: :delete, path: member_path(id), as: Webhook)
  end

  defp member_path(id), do: "/webhooks/" <> Request.encode(id)
end
