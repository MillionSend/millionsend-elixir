defmodule MillionSend.Receiving.Attachment do
  @moduledoc """
  An attachment of a received email, or of a thread email (`id`, `filename` and
  `size` only; the id of an attachment the inbox sent is its position, `"0"`,
  `"1"`, …). `download_url` is a signed link valid for one hour, set by the
  attachment endpoints; it answers 410 `email_blocked` when the email carries
  malware.
  """
  @type t :: %__MODULE__{}
  defstruct [
    :object,
    :id,
    :filename,
    :size,
    :content_type,
    :content_disposition,
    :content_id,
    :download_url,
    :expires_at
  ]

  @doc false
  def cast_list(nil), do: nil
  def cast_list(list), do: Enum.map(list, &MillionSend.Request.cast_struct(__MODULE__, &1))
end

defmodule MillionSend.Receiving.ReceivedEmail do
  @moduledoc """
  A received email. Everything in it was written by whoever sent the message:
  show its HTML only in a sandbox.

  List items leave the body fields (`html`, `text`, `headers`, `authentication`,
  `raw`) and the detail-only extensions `nil`. Extension fields:

    * `inbox_id`, `thread_id` — the inbox this view reads it through
    * `inboxes` — every inbox it was delivered to (owner views), as maps
    * `screening` — a map with `"verdict"`, `"sender_trust"` and, on the detail,
      `"quarantine_reason"`, `"reasons"`, `"injection_score"`,
      `"phishing_score"` and `"hidden_text_removed"`
    * `spam_verdict`, `spam_score`, `virus_verdict`, `virus_signature`
    * `extracted_text` — the reply without quotes, signature or hidden text
    * `extracted` — a map with `"kinds"` and, on the detail, `"code"`, `"link"`,
      `"link_domain_matches_sender"` and `"ambiguous"`
    * `read` — read state in the inbox this view reads it through

  Every verdict is a plain string: the API may add values.
  """
  alias MillionSend.Receiving.Attachment

  @type t :: %__MODULE__{}
  defstruct [
    :object,
    :id,
    :from,
    :to,
    :cc,
    :bcc,
    :reply_to,
    :subject,
    :created_at,
    :received_for,
    :message_id,
    :attachments,
    :html,
    :html_format,
    :text,
    :headers,
    :authentication,
    :raw,
    :inbox_id,
    :thread_id,
    :inboxes,
    :screening,
    :spam_verdict,
    :spam_score,
    :virus_verdict,
    :virus_signature,
    :extracted_text,
    :extracted,
    :read,
    :deleted
  ]

  @doc false
  def cast(map) do
    email = MillionSend.Request.cast_struct(__MODULE__, map)
    %{email | attachments: Attachment.cast_list(email.attachments)}
  end
end

defmodule MillionSend.Receiving.EmailList do
  @moduledoc """
  A page of received mail. With `wait:`, `held` lists the matching emails that
  arrived but are held (quarantined or being screened), by id and why only: maps
  with `"id"`, `"inbox_id"`, `"reason"` (`"pending"` or `"quarantined"`),
  `"quarantine_reason"` and `"created_at"`. It is `nil` otherwise.
  """
  alias MillionSend.Receiving.ReceivedEmail

  @type t :: %__MODULE__{
          object: String.t() | nil,
          data: list(),
          has_more: boolean(),
          held: list() | nil
        }
  defstruct object: "list", data: [], has_more: false, held: nil

  @doc false
  def cast(map) do
    %__MODULE__{
      object: map["object"],
      data: Enum.map(map["data"] || [], &ReceivedEmail.cast/1),
      has_more: map["has_more"] || false,
      held: map["held"]
    }
  end
end

defmodule MillionSend.Receiving do
  @moduledoc """
  Mail received at the team's receiving domains and inboxes.

      {:ok, page} = MillionSend.Receiving.list(inbox_id: inbox_id, from: "acme.dev")
      {:ok, email} = MillionSend.Receiving.get(id)
      email.extracted_text

      # Long-poll: returns as soon as matching mail arrives, or an empty page
      # when the wait (up to 50 seconds) ends.
      {:ok, page} = MillionSend.Receiving.list(inbox_id: inbox_id, wait: 30)

  `reply/4` and `forward/4` return `{:ok, {:sent, %MillionSend.Inboxes.ThreadEmail{}}}`
  when the email went out (`id`, `thread_id` and `inbox_id` set; the last two
  are `nil` for mail no inbox took), or
  `{:ok, {:draft, %MillionSend.Inboxes.Draft{}}}` when the inbox's send rules
  held it for a person to approve (the API answers 202).
  Their params are sent as given: `text`, `html`, `subject`, `cc`, `bcc`,
  `reply_all`, `requires_approval`, `from` and `inbox_id`; `forward/4` also takes
  `to` (required) and `mode` (`"inline"`, the default, or `"attachment"`).
  """

  alias MillionSend.{Client, Request}
  alias MillionSend.Inboxes.{Draft, ThreadEmail}
  alias MillionSend.Receiving.{EmailList, ReceivedEmail}

  @doc """
  `GET /emails/receiving` — newest first. Options: `limit:`, `after:`,
  `before:`, `wait:` (0..50 seconds), `since:` (an ISO 8601 string with an
  offset, as `DateTime.to_iso8601/1` writes it), `inbox_id:`, `to:` (an address
  the message was delivered to), `from:` (an address, or a domain covering its
  subdomains), `subject_contains:`, `unread:` (read state in one inbox: a team
  key needs `inbox_id:`, an inbox-scoped key reads its own inbox),
  `include_quarantined: true` (held mail too) and `quarantined: true` (held mail
  only); the last two need a full-access key not scoped to an inbox.

  An `inbox_id:` that doesn't exist answers 404 `"not_found"` at once, even
  with `wait:`.
  """
  @spec list(Client.t() | keyword()) :: {:ok, EmailList.t()} | {:error, MillionSend.Error.t()}
  def list(), do: list(MillionSend.client(), [])
  def list(%Client{} = client), do: list(client, [])
  def list(opts) when is_list(opts), do: list(MillionSend.client(), opts)

  @spec list(Client.t(), keyword()) :: {:ok, EmailList.t()} | {:error, MillionSend.Error.t()}
  def list(%Client{} = client, opts) when is_list(opts) do
    query =
      Request.list_query(opts) ++
        [
          wait: opts[:wait],
          since: opts[:since],
          inbox_id: opts[:inbox_id],
          to: opts[:to],
          from: opts[:from],
          subject_contains: opts[:subject_contains],
          unread: opts[:unread],
          include_quarantined: if(opts[:include_quarantined], do: true),
          quarantined: if(opts[:quarantined], do: true)
        ]

    Request.run(client,
      method: :get,
      path: "/emails/receiving",
      query: query,
      wait: opts[:wait],
      as: &EmailList.cast/1
    )
  end

  @doc """
  `GET /emails/receiving/:id` — option `html_format:` (`"data_uri"`, the
  default, or `"cid"`). Held mail read by an inbox-scoped key answers 403
  `email_quarantined`.
  """
  @spec get(String.t()) :: {:ok, ReceivedEmail.t()} | {:error, MillionSend.Error.t()}
  def get(id) when is_binary(id), do: get(MillionSend.client(), id, [])

  @spec get(Client.t() | String.t(), String.t() | keyword()) ::
          {:ok, ReceivedEmail.t()} | {:error, MillionSend.Error.t()}
  def get(%Client{} = client, id) when is_binary(id), do: get(client, id, [])
  def get(id, opts) when is_binary(id) and is_list(opts), do: get(MillionSend.client(), id, opts)

  @spec get(Client.t(), String.t(), keyword()) ::
          {:ok, ReceivedEmail.t()} | {:error, MillionSend.Error.t()}
  def get(%Client{} = client, id, opts) when is_binary(id) and is_list(opts) do
    Request.run(client,
      method: :get,
      path: member_path(id),
      query: [html_format: opts[:html_format]],
      as: &ReceivedEmail.cast/1
    )
  end

  @doc "`POST /emails/receiving/:id/reply` — option `idempotency_key:`."
  @spec reply(String.t(), map()) :: Draft.send_result(ThreadEmail.t())
  def reply(id, params) when is_binary(id), do: reply(MillionSend.client(), id, params, [])

  @spec reply(Client.t() | String.t(), String.t() | map(), map() | keyword()) ::
          Draft.send_result(ThreadEmail.t())
  def reply(%Client{} = client, id, params) when is_binary(id), do: reply(client, id, params, [])

  def reply(id, params, opts) when is_binary(id) and is_list(opts),
    do: reply(MillionSend.client(), id, params, opts)

  @spec reply(Client.t(), String.t(), map(), keyword()) :: Draft.send_result(ThreadEmail.t())
  def reply(%Client{} = client, id, params, opts) when is_binary(id) and is_list(opts) do
    Draft.send_or_hold(client, member_path(id) <> "/reply", params, opts, &ThreadEmail.cast/1)
  end

  @doc """
  `POST /emails/receiving/:id/forward` — option `idempotency_key:`. An email
  that carries malware answers 403 `email_quarantined`.
  """
  @spec forward(String.t(), map()) :: Draft.send_result(ThreadEmail.t())
  def forward(id, params) when is_binary(id), do: forward(MillionSend.client(), id, params, [])

  @spec forward(Client.t() | String.t(), String.t() | map(), map() | keyword()) ::
          Draft.send_result(ThreadEmail.t())
  def forward(%Client{} = client, id, params) when is_binary(id),
    do: forward(client, id, params, [])

  def forward(id, params, opts) when is_binary(id) and is_list(opts),
    do: forward(MillionSend.client(), id, params, opts)

  @spec forward(Client.t(), String.t(), map(), keyword()) :: Draft.send_result(ThreadEmail.t())
  def forward(%Client{} = client, id, params, opts) when is_binary(id) and is_list(opts) do
    Draft.send_or_hold(client, member_path(id) <> "/forward", params, opts, &ThreadEmail.cast/1)
  end

  @doc "`DELETE /emails/receiving/:id` — erase it now (a full-access key not scoped to an inbox)."
  @spec remove(Client.t(), String.t()) ::
          {:ok, ReceivedEmail.t()} | {:error, MillionSend.Error.t()}
  def remove(client \\ MillionSend.client(), id) when is_binary(id) do
    Request.run(client, method: :delete, path: member_path(id), as: &ReceivedEmail.cast/1)
  end

  @doc false
  def member_path(id), do: "/emails/receiving/" <> Request.encode(id)
end

defmodule MillionSend.Receiving.Attachments do
  @moduledoc """
  The attachments of a received email, each with a signed `download_url` valid
  for one hour that needs no API key.
  """

  alias MillionSend.{Client, Receiving, Request}
  alias MillionSend.Receiving.Attachment

  @doc "`GET /emails/receiving/:email_id/attachments` — all of them unless `limit:` is given; also `after:`, `before:`."
  @spec list(String.t()) :: {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(email_id) when is_binary(email_id), do: list(MillionSend.client(), email_id, [])

  @spec list(Client.t() | String.t(), String.t() | keyword()) ::
          {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(%Client{} = client, email_id) when is_binary(email_id), do: list(client, email_id, [])

  def list(email_id, opts) when is_binary(email_id) and is_list(opts),
    do: list(MillionSend.client(), email_id, opts)

  @spec list(Client.t(), String.t(), keyword()) ::
          {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(%Client{} = client, email_id, opts) when is_binary(email_id) and is_list(opts) do
    Request.run(client,
      method: :get,
      path: Receiving.member_path(email_id) <> "/attachments",
      query: Request.list_query(opts),
      as: {:list, Attachment}
    )
  end

  @doc "`GET /emails/receiving/:email_id/attachments/:id`"
  @spec get(Client.t(), String.t(), String.t()) ::
          {:ok, Attachment.t()} | {:error, MillionSend.Error.t()}
  def get(client \\ MillionSend.client(), email_id, id)
      when is_binary(email_id) and is_binary(id) do
    Request.run(client,
      method: :get,
      path: Receiving.member_path(email_id) <> "/attachments/" <> Request.encode(id),
      as: Attachment
    )
  end
end
