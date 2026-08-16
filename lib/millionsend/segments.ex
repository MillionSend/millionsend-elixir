defmodule MillionSend.Segments.Segment do
  @moduledoc "A dynamic segment — a saved filter over an audience's contacts."
  defstruct [:object, :id, :name, :audience_id, :filter, :created_at, :contact_count, :deleted]
end

defmodule MillionSend.Segments do
  @moduledoc """
  Dynamic segments — a saved filter over an audience's contacts. A MillionSend
  extension with no Resend equivalent; the wire path is `/segments2`. `get/2`
  returns a live `contact_count`.

      MillionSend.Segments.create(%{
        name: "Pro plan",
        audience_id: aud,
        filter: %{match: :all, conditions: [%{field: "property:plan", op: "equals", value: "pro"}]}
      })
  """

  alias MillionSend.{Client, Request}
  alias MillionSend.Segments.Segment

  @doc "`POST /segments2`"
  @spec create(Client.t(), map()) :: {:ok, Segment.t()} | {:error, MillionSend.Error.t()}
  def create(client \\ MillionSend.client(), params) when is_map(params) do
    Request.run(client,
      method: :post,
      path: "/segments2",
      body: Request.take(params, [:name, :audience_id, :filter]),
      as: Segment
    )
  end

  @doc "`GET /segments2/:id`"
  @spec get(Client.t(), String.t()) :: {:ok, Segment.t()} | {:error, MillionSend.Error.t()}
  def get(client \\ MillionSend.client(), id) when is_binary(id) do
    Request.run(client, method: :get, path: "/segments2/" <> Request.encode(id), as: Segment)
  end

  @doc "`GET /segments2` — accepts `limit:`, `after:`, `before:`."
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
      path: "/segments2",
      query: Request.list_query(opts),
      as: {:list, Segment}
    )
  end

  @doc "`PATCH /segments2/:id`"
  @spec update(Client.t(), String.t(), map()) ::
          {:ok, Segment.t()} | {:error, MillionSend.Error.t()}
  def update(client \\ MillionSend.client(), id, params) when is_binary(id) and is_map(params) do
    Request.run(client,
      method: :patch,
      path: "/segments2/" <> Request.encode(id),
      body: Request.take(params, [:name, :filter]),
      as: Segment
    )
  end

  @doc "`DELETE /segments2/:id`"
  @spec remove(Client.t(), String.t()) :: {:ok, Segment.t()} | {:error, MillionSend.Error.t()}
  def remove(client \\ MillionSend.client(), id) when is_binary(id) do
    Request.run(client, method: :delete, path: "/segments2/" <> Request.encode(id), as: Segment)
  end
end
