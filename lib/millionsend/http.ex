defmodule MillionSend.HTTP do
  @moduledoc """
  Behaviour for the swappable HTTP layer. The default is `MillionSend.HTTP.Req`;
  tests inject a stub by building a client with `http_client:` set to a module
  implementing this behaviour.
  """

  @typedoc """
  `receive_timeout` (milliseconds) is set only for a long-poll, which the API
  may hold open for up to 50 seconds.
  """
  @type request :: %{
          required(:method) => :get | :post | :patch | :delete,
          required(:url) => String.t(),
          required(:headers) => [{String.t(), String.t()}],
          required(:body) => iodata() | nil,
          optional(:receive_timeout) => pos_integer()
        }

  @typedoc """
  `headers` is optional; without it errors carry `retry_after: nil`.
  """
  @type response :: %{
          required(:status) => non_neg_integer(),
          required(:body) => binary() | nil,
          optional(:headers) => [{String.t(), String.t()}]
        }

  @callback request(request()) :: {:ok, response()} | {:error, term()}
end

defmodule MillionSend.HTTP.Req do
  @moduledoc "Default `MillionSend.HTTP` implementation, backed by Req."
  @behaviour MillionSend.HTTP

  @impl true
  def request(%{method: method, url: url, headers: headers, body: body} = request) do
    case Req.request(
           [
             method: method,
             url: url,
             headers: headers,
             body: body,
             decode_body: false,
             retry: false
           ] ++ Map.to_list(Map.take(request, [:receive_timeout]))
         ) do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: resp_body}} ->
        # Req holds headers as a map of value lists, or as a list of pairs under
        # its legacy_headers_as_lists config; List.wrap reads both.
        headers =
          for {name, values} <- resp_headers, value <- List.wrap(values), do: {name, value}

        {:ok, %{status: status, body: resp_body, headers: headers}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
