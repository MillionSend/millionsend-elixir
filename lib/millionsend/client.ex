defmodule MillionSend.Client do
  @moduledoc """
  A resolved MillionSend client: API key, base URL, User-Agent and the HTTP
  module to run requests through. Build one with `MillionSend.client/1`.
  """

  @default_base_url "http://localhost:3001"
  @version Mix.Project.config()[:version]
  @user_agent "millionsend-elixir/#{@version}"

  @type t :: %__MODULE__{
          api_key: String.t(),
          base_url: String.t(),
          user_agent: String.t(),
          http_client: module()
        }

  defstruct [:api_key, :base_url, :user_agent, http_client: MillionSend.HTTP.Req]

  @doc """
  Resolves a client from (in precedence order) the given `opts`, the
  `config :millionsend, MillionSend.Client` application env, OS environment
  variables, and finally the built-in defaults.

  Options: `:api_key`, `:base_url`, `:user_agent` (a suffix appended to the
  SDK's own User-Agent token), `:http_client` (a module implementing
  `MillionSend.HTTP`, for tests/proxies).
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    config = Application.get_env(:millionsend, __MODULE__, [])

    api_key = opts[:api_key] || config[:api_key] || System.get_env("MILLIONSEND_API_KEY")

    unless is_binary(api_key) and api_key != "" do
      raise ArgumentError,
            "Missing MillionSend API key. Pass MillionSend.client(api_key: ...), set " <>
              "config :millionsend, MillionSend.Client, api_key: ..., or the " <>
              "MILLIONSEND_API_KEY environment variable."
    end

    base_url =
      (opts[:base_url] || config[:base_url] || System.get_env("MILLIONSEND_BASE_URL") ||
         @default_base_url)
      |> String.trim_trailing("/")

    %__MODULE__{
      api_key: api_key,
      base_url: base_url,
      http_client: opts[:http_client] || config[:http_client] || MillionSend.HTTP.Req,
      user_agent: user_agent(opts[:user_agent] || config[:user_agent])
    }
  end

  defp user_agent(nil), do: @user_agent
  defp user_agent(suffix) when is_binary(suffix), do: @user_agent <> " " <> suffix
end
