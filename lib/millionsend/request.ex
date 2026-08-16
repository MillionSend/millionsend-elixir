defmodule MillionSend.Request do
  @moduledoc false
  # Internal request pipeline shared by every resource: builds the URL, headers
  # and JSON body, runs the request through the client's HTTP module, and casts
  # the response into `{:ok, struct}` / `{:error, %MillionSend.Error{}}`.

  alias MillionSend.{Client, Error}

  @spec run(Client.t(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def run(%Client{} = client, opts) do
    method = Keyword.fetch!(opts, :method)
    path = Keyword.fetch!(opts, :path)
    body = Keyword.get(opts, :body)
    query = Keyword.get(opts, :query)
    idempotency_key = Keyword.get(opts, :idempotency_key)
    as = Keyword.get(opts, :as)

    url = client.base_url <> path <> encode_query(query)
    encoded = if is_nil(body), do: nil, else: Jason.encode!(body)
    headers = headers(client, method, encoded, idempotency_key)

    case client.http_client.request(%{method: method, url: url, headers: headers, body: encoded}) do
      {:ok, %{status: status, body: raw}} -> handle(status, raw, as)
      {:error, reason} -> {:error, Error.transport(reason)}
    end
  end

  @doc """
  Picks `keys` (atoms) that are present in `map`, preserving `nil` values so an
  explicit `nil` still clears a field on PATCH; absent keys are dropped. Accepts
  atom or string keys in the input.
  """
  @spec take(map(), [atom()]) :: map()
  def take(map, keys) when is_map(map) do
    Enum.reduce(keys, %{}, fn key, acc ->
      cond do
        Map.has_key?(map, key) -> Map.put(acc, key, Map.get(map, key))
        Map.has_key?(map, to_string(key)) -> Map.put(acc, key, Map.get(map, to_string(key)))
        true -> acc
      end
    end)
  end

  @doc "Percent-encodes a single path segment the way `encodeURIComponent` does."
  @spec encode(term()) :: String.t()
  def encode(segment), do: URI.encode(to_string(segment), &URI.char_unreserved?/1)

  @doc false
  @spec list_query(keyword() | map()) :: keyword()
  def list_query(opts), do: [limit: opts[:limit], after: opts[:after], before: opts[:before]]

  defp handle(status, raw, as) do
    parsed = decode(raw)

    if status in 200..299 do
      {:ok, cast(parsed, as)}
    else
      {:error, Error.from_body(parsed, status)}
    end
  end

  defp headers(client, method, encoded, idempotency_key) do
    base = [
      {"authorization", "Bearer " <> client.api_key},
      {"accept", "application/json"},
      {"user-agent", client.user_agent}
    ]

    base =
      if not is_nil(encoded) and method in [:post, :patch],
        do: [{"content-type", "application/json"} | base],
        else: base

    # Idempotency is POST-only on the wire.
    if idempotency_key && method == :post,
      do: [{"idempotency-key", idempotency_key} | base],
      else: base
  end

  defp encode_query(nil), do: ""

  defp encode_query(query) do
    query
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> case do
      [] -> ""
      pairs -> "?" <> URI.encode_query(pairs)
    end
  end

  defp decode(nil), do: nil
  defp decode(""), do: nil

  defp decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> parsed
      {:error, _} -> body
    end
  end

  defp decode(body), do: body

  defp cast(parsed, nil), do: parsed

  defp cast(parsed, {:list, module}) when is_map(parsed) do
    %MillionSend.List{
      object: parsed["object"],
      has_more: parsed["has_more"] || false,
      data: Enum.map(parsed["data"] || [], &cast_struct(module, &1))
    }
  end

  # A bare `{ data: [...] }` body (topics, batch) -> a plain list of structs.
  defp cast(parsed, {:data, module}) when is_map(parsed) do
    Enum.map(parsed["data"] || [], &cast_struct(module, &1))
  end

  defp cast(parsed, module) when is_atom(module) and is_map(parsed),
    do: cast_struct(module, parsed)

  defp cast(parsed, _as), do: parsed

  defp cast_struct(module, map) when is_map(map) do
    fields = module.__struct__() |> Map.from_struct() |> Map.keys()
    data = for f <- fields, Map.has_key?(map, to_string(f)), into: %{}, do: {f, map[to_string(f)]}
    struct(module, data)
  end
end
