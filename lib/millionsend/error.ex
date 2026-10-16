defmodule MillionSend.Error do
  @moduledoc """
  The error every non-2xx response carries, plus the client-side/transport case.

  `name` is the stable snake_case discriminant you can match on
  (`"validation_error"`, `"not_found"`, `"restricted_api_key"`, …). `status_code`
  is `nil` when the request never reached the API (a transport failure).

  `retry_after` is the seconds the response's `retry-after` header asks to wait
  before trying again, or `nil` when it sent none (and on client-side
  failures). MillionSend sends it on its 429s and on 503
  `"name_review_unavailable"`. The SDK never retries on its own.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          message: String.t(),
          status_code: non_neg_integer() | nil,
          retry_after: non_neg_integer() | nil
        }

  defexception [:name, :message, :status_code, :retry_after]

  @impl true
  def message(%__MODULE__{name: name, message: message}), do: "#{name}: #{message}"

  @doc false
  @spec from_body(term(), non_neg_integer(), [{String.t(), String.t()}]) :: t()
  def from_body(body, status, headers) when is_map(body) do
    %__MODULE__{
      name: string_or(body["name"], "application_error"),
      message: string_or(body["message"], "Request failed with status #{status}"),
      # The wire error body uses the camelCase key `statusCode`.
      status_code: if(is_integer(body["statusCode"]), do: body["statusCode"], else: status),
      retry_after: retry_after(headers)
    }
  end

  def from_body(_body, status, headers) do
    %__MODULE__{
      name: "application_error",
      message: "Request failed with status #{status}",
      status_code: status,
      retry_after: retry_after(headers)
    }
  end

  @doc false
  @spec transport(term()) :: t()
  def transport(reason) do
    %__MODULE__{name: "application_error", message: reason_message(reason), status_code: nil}
  end

  defp string_or(value, _default) when is_binary(value), do: value
  defp string_or(_value, default), do: default

  # The API sends retry-after as whole seconds; an HTTP-date value reads as nil.
  defp retry_after(headers) do
    Enum.find_value(headers, fn {name, value} ->
      with "retry-after" <- String.downcase(name),
           {seconds, ""} when seconds >= 0 <- Integer.parse(String.trim(value)) do
        seconds
      else
        _ -> nil
      end
    end)
  end

  defp reason_message(%{__exception__: true} = exception), do: Exception.message(exception)
  defp reason_message(reason) when is_binary(reason), do: reason
  defp reason_message(reason), do: inspect(reason)
end
