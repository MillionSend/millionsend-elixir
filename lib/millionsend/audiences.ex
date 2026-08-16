defmodule MillionSend.Audiences.Audience do
  @moduledoc "A named contact list."
  defstruct [:object, :id, :name, :created_at, :deleted]
end

defmodule MillionSend.Audiences do
  @moduledoc """
  Audiences — named contact lists. Resend-compatible, so a migrating app's
  `audiences.*` calls port straight over. (MillionSend's dynamic-filter
  `MillionSend.Segments` are a separate, richer resource.)
  """

  alias MillionSend.{Client, Request}
  alias MillionSend.Audiences.Audience

  @doc "`POST /audiences`"
  @spec create(Client.t(), map()) :: {:ok, Audience.t()} | {:error, MillionSend.Error.t()}
  def create(client \\ MillionSend.client(), params) when is_map(params) do
    Request.run(client,
      method: :post,
      path: "/audiences",
      body: Request.take(params, [:name]),
      as: Audience
    )
  end

  @doc "`GET /audiences/:id`"
  @spec get(Client.t(), String.t()) :: {:ok, Audience.t()} | {:error, MillionSend.Error.t()}
  def get(client \\ MillionSend.client(), id) when is_binary(id) do
    Request.run(client, method: :get, path: "/audiences/" <> Request.encode(id), as: Audience)
  end

  @doc "`GET /audiences` — accepts `limit:`, `after:`, `before:`."
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
      path: "/audiences",
      query: Request.list_query(opts),
      as: {:list, Audience}
    )
  end

  @doc "`DELETE /audiences/:id`"
  @spec remove(Client.t(), String.t()) :: {:ok, Audience.t()} | {:error, MillionSend.Error.t()}
  def remove(client \\ MillionSend.client(), id) when is_binary(id) do
    Request.run(client, method: :delete, path: "/audiences/" <> Request.encode(id), as: Audience)
  end
end
