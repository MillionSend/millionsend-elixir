defmodule MillionSend.Emails.Email do
  @moduledoc "An email. `send/2` and `cancel/2` populate only `id`/`object`."
  defstruct [
    :object,
    :id,
    :from,
    :to,
    :cc,
    :bcc,
    :reply_to,
    :subject,
    :html,
    :text,
    :created_at,
    :scheduled_at,
    :message_id,
    :last_event
  ]
end

defmodule MillionSend.Emails do
  @moduledoc """
  Send, fetch and cancel emails.

  Input maps use snake_case keys (`:reply_to`, `:scheduled_at`); `:to`, `:cc`,
  `:bcc` and `:reply_to` take a string or a list of strings.

      MillionSend.Emails.send(%{
        from: "Acme <onboarding@acme.dev>",
        to: "delivered@resend.dev",
        subject: "Hello",
        html: "<strong>it works</strong>"
      })
  """

  # `send/1` here is the email action, not `Kernel.send/2`.
  import Kernel, except: [send: 2]

  alias MillionSend.{Client, Request}
  alias MillionSend.Emails.Email

  @fields [:from, :to, :subject, :html, :text, :cc, :bcc, :reply_to, :scheduled_at, :tags]

  @doc """
  `POST /emails`. Accepts an optional leading client and an optional
  `idempotency_key:` in the trailing options.
  """
  @spec send(map()) :: {:ok, Email.t()} | {:error, MillionSend.Error.t()}
  def send(params) when is_map(params), do: send(MillionSend.client(), params, [])

  @spec send(Client.t() | map(), map() | keyword()) ::
          {:ok, Email.t()} | {:error, MillionSend.Error.t()}
  def send(%Client{} = client, params) when is_map(params), do: send(client, params, [])

  def send(params, opts) when is_map(params) and is_list(opts),
    do: send(MillionSend.client(), params, opts)

  @spec send(Client.t(), map(), keyword()) :: {:ok, Email.t()} | {:error, MillionSend.Error.t()}
  def send(%Client{} = client, params, opts) when is_map(params) and is_list(opts) do
    Request.run(client,
      method: :post,
      path: "/emails",
      body: Request.take(params, @fields),
      idempotency_key: opts[:idempotency_key],
      as: Email
    )
  end

  @doc "`POST /emails/batch` — 1..100 emails in one call; supports `idempotency_key:`."
  @spec send_batch([map()]) :: {:ok, [Email.t()]} | {:error, MillionSend.Error.t()}
  def send_batch(list) when is_list(list), do: send_batch(MillionSend.client(), list, [])

  @spec send_batch(Client.t() | [map()], [map()] | keyword()) ::
          {:ok, [Email.t()]} | {:error, MillionSend.Error.t()}
  def send_batch(%Client{} = client, list) when is_list(list), do: send_batch(client, list, [])

  def send_batch(list, opts) when is_list(list) and is_list(opts),
    do: send_batch(MillionSend.client(), list, opts)

  @spec send_batch(Client.t(), [map()], keyword()) ::
          {:ok, [Email.t()]} | {:error, MillionSend.Error.t()}
  def send_batch(%Client{} = client, list, opts) when is_list(list) and is_list(opts) do
    Request.run(client,
      method: :post,
      path: "/emails/batch",
      body: Enum.map(list, &Request.take(&1, @fields)),
      idempotency_key: opts[:idempotency_key],
      as: {:data, Email}
    )
  end

  @doc "`GET /emails/:id`"
  @spec get(Client.t(), String.t()) :: {:ok, Email.t()} | {:error, MillionSend.Error.t()}
  def get(client \\ MillionSend.client(), id) when is_binary(id) do
    Request.run(client, method: :get, path: "/emails/" <> Request.encode(id), as: Email)
  end

  @doc "`POST /emails/:id/cancel` — only scheduled, unsent emails."
  @spec cancel(Client.t(), String.t()) :: {:ok, Email.t()} | {:error, MillionSend.Error.t()}
  def cancel(client \\ MillionSend.client(), id) when is_binary(id) do
    Request.run(client,
      method: :post,
      path: "/emails/" <> Request.encode(id) <> "/cancel",
      as: Email
    )
  end
end
