defmodule MillionSend.Inboxes.Inbox do
  @moduledoc """
  An inbox: one address that receives mail, read by an agent (`kind: "agent"`)
  or by people (`"human"`). List items carry `id`, `name`, `email_address`,
  `from_name`, `unread`, `last_received`, `kind`, `shared` and `expires_at`.
  `domain_id` of a shared-domain inbox is the team's shared subdomain id.
  `remove/2` populates `id` plus `deleted`.
  """
  @type t :: %__MODULE__{}
  defstruct [
    :object,
    :id,
    :name,
    :email_address,
    :domain_id,
    :receiving_address,
    :from_name,
    :unread,
    :drafts,
    :last_received,
    :created_at,
    :kind,
    :shared,
    :expires_at,
    :quarantined,
    :pending_approval,
    :deleted
  ]
end

defmodule MillionSend.Inboxes do
  @moduledoc """
  Inboxes for agents and people, with threads in both directions. The paths
  mirror Resend's Inboxes API; `kind`, `shared`, `expires_at`, safety, codes and
  quarantine are MillionSend extensions. Sub-resources:
  `MillionSend.Inboxes.Safety`, `MillionSend.Inboxes.Codes`,
  `MillionSend.Inboxes.Quarantine`, `MillionSend.Inboxes.Labels`,
  `MillionSend.Inboxes.Threads`, `MillionSend.Inboxes.ThreadEmails` and
  `MillionSend.Inboxes.Drafts`.

  Input maps are sent as given: `create/2` accepts `email_address` (omit it for
  a random address on the shared domain), `name`, `from_name`, `forwarding`,
  `kind` (`"agent"`, the default, or `"human"`), `expires_in` (like `"24h"` or
  `"30d"`) and `safety` (a partial `MillionSend.Inboxes.Safety` map);
  `update/3` accepts `name`, `from_name` (`""` removes it) and `expires_in`
  (`nil` for never).

      {:ok, inbox} = MillionSend.Inboxes.create(%{name: "Signup bot", expires_in: "24h"})
      {:ok, inbox} = MillionSend.Inboxes.get("bot@acme.dev")

  Folder, verdict, kind and status values are plain strings: the API may add
  values.
  """

  alias MillionSend.{Client, Request}
  alias MillionSend.Inboxes.Inbox

  @doc "`POST /inboxes` — 409 when the address is taken, 403 at the plan's inbox limit."
  @spec create(Client.t(), map()) :: {:ok, Inbox.t()} | {:error, MillionSend.Error.t()}
  def create(client \\ MillionSend.client(), params) when is_map(params) do
    Request.run(client, method: :post, path: "/inboxes", body: params, as: Inbox)
  end

  @doc "`GET /inboxes` — newest first. Accepts `limit:`, `after:`, `before:` and `kind:`."
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
      path: "/inboxes",
      query: Request.list_query(opts) ++ [kind: opts[:kind]],
      as: {:list, Inbox}
    )
  end

  @doc "`GET /inboxes/:id_or_email` — by id or by address (case-insensitive)."
  @spec get(Client.t(), String.t()) :: {:ok, Inbox.t()} | {:error, MillionSend.Error.t()}
  def get(client \\ MillionSend.client(), id_or_email) when is_binary(id_or_email) do
    Request.run(client, method: :get, path: path(id_or_email), as: Inbox)
  end

  @doc "`PATCH /inboxes/:id` — returns the updated inbox."
  @spec update(Client.t(), String.t(), map()) ::
          {:ok, Inbox.t()} | {:error, MillionSend.Error.t()}
  def update(client \\ MillionSend.client(), id, params) when is_binary(id) and is_map(params) do
    Request.run(client, method: :patch, path: path(id), body: params, as: Inbox)
  end

  @doc "`DELETE /inboxes/:id` — removes its threads, drafts and labels and revokes its keys."
  @spec remove(Client.t(), String.t()) :: {:ok, Inbox.t()} | {:error, MillionSend.Error.t()}
  def remove(client \\ MillionSend.client(), id) when is_binary(id) do
    Request.run(client, method: :delete, path: path(id), as: Inbox)
  end

  @doc false
  def path(id), do: "/inboxes/" <> Request.encode(id)
end

defmodule MillionSend.Inboxes.Safety do
  @moduledoc """
  An inbox's safety rules (a MillionSend extension): `accept_from`
  (`"anyone" | "verified" | "allowlist"`; mail failing it is quarantined),
  `allowlist` (`local@domain`, or `*@domain` for a domain and its subdomains),
  `owner_addresses`, `screening` (the prompt-injection screen), `extract_codes`,
  `send_policy` (`"reply_only" | "allowlist" | "open"`), `require_approval`,
  `private_codes`, `send_cap` (unattended recipients per UTC day; `nil` for no
  cap) and `forward_to`.

      MillionSend.Inboxes.Safety.update(inbox_id, %{accept_from: "allowlist", allowlist: ["*@partner.dev"]})

  `update/3` changes only the keys given (`send_cap: nil` removes the cap) and
  returns every rule. Inbox-scoped keys can read the rules, never change them.
  """

  alias MillionSend.{Client, Inboxes, Request}

  @type t :: %__MODULE__{}
  defstruct [
    :object,
    :inbox_id,
    :accept_from,
    :allowlist,
    :owner_addresses,
    :screening,
    :extract_codes,
    :send_policy,
    :require_approval,
    :private_codes,
    :send_cap,
    :forward_to
  ]

  @doc "`GET /inboxes/:inbox_id/safety`"
  @spec get(Client.t(), String.t()) :: {:ok, t()} | {:error, MillionSend.Error.t()}
  def get(client \\ MillionSend.client(), inbox_id) when is_binary(inbox_id) do
    Request.run(client, method: :get, path: Inboxes.path(inbox_id) <> "/safety", as: __MODULE__)
  end

  @doc "`PATCH /inboxes/:inbox_id/safety`"
  @spec update(Client.t(), String.t(), map()) :: {:ok, t()} | {:error, MillionSend.Error.t()}
  def update(client \\ MillionSend.client(), inbox_id, params)
      when is_binary(inbox_id) and is_map(params) do
    Request.run(client,
      method: :patch,
      path: Inboxes.path(inbox_id) <> "/safety",
      body: params,
      as: __MODULE__
    )
  end
end

defmodule MillionSend.Inboxes.VerificationCode do
  @moduledoc """
  The newest verification code or sign-in link an inbox received. `status` is
  `"found" | "none" | "ambiguous" | "timeout"` (a wait that ended empty);
  `kind` is `"otp" | "link"` when found, with `code` or `url`. The link is never
  fetched.
  """
  @type t :: %__MODULE__{}
  defstruct [
    :object,
    :status,
    :kind,
    :code,
    :url,
    :link_domain_matches_sender,
    :email_id,
    :from,
    :received_at,
    :sender_trust
  ]
end

defmodule MillionSend.Inboxes.Codes do
  @moduledoc "Verification codes and sign-in links an inbox received (a MillionSend extension)."

  alias MillionSend.{Client, Inboxes, Request}
  alias MillionSend.Inboxes.VerificationCode

  @doc """
  `GET /inboxes/:inbox_id/codes/latest` — options `from:` (an address, or a
  domain covering its subdomains), `wait:` (0..50 seconds to wait for a code)
  and `max_age:` (60..86400 seconds; the API defaults to 600).

      {:ok, %{status: "found", code: code}} =
        MillionSend.Inboxes.Codes.latest(inbox_id, from: "github.com", wait: 30)
  """
  @spec latest(String.t()) :: {:ok, VerificationCode.t()} | {:error, MillionSend.Error.t()}
  def latest(inbox_id) when is_binary(inbox_id), do: latest(MillionSend.client(), inbox_id, [])

  @spec latest(Client.t() | String.t(), String.t() | keyword()) ::
          {:ok, VerificationCode.t()} | {:error, MillionSend.Error.t()}
  def latest(%Client{} = client, inbox_id) when is_binary(inbox_id),
    do: latest(client, inbox_id, [])

  def latest(inbox_id, opts) when is_binary(inbox_id) and is_list(opts),
    do: latest(MillionSend.client(), inbox_id, opts)

  @spec latest(Client.t(), String.t(), keyword()) ::
          {:ok, VerificationCode.t()} | {:error, MillionSend.Error.t()}
  def latest(%Client{} = client, inbox_id, opts) when is_binary(inbox_id) and is_list(opts) do
    Request.run(client,
      method: :get,
      path: Inboxes.path(inbox_id) <> "/codes/latest",
      query: [from: opts[:from], wait: opts[:wait], max_age: opts[:max_age]],
      wait: opts[:wait],
      as: VerificationCode
    )
  end
end

defmodule MillionSend.Inboxes.QuarantinedEmail do
  @moduledoc """
  An email held in an inbox's quarantine: `quarantine_reason` (e.g.
  `"failed_auth"`, `"not_allowlisted"`, `"injection"`, `"virus"`),
  `sender_trust`, the screening scores and `virus_signature`.
  """
  @type t :: %__MODULE__{}
  defstruct [
    :id,
    :thread_id,
    :from,
    :subject,
    :received_at,
    :quarantine_reason,
    :sender_trust,
    :injection_score,
    :phishing_score,
    :virus_signature
  ]
end

defmodule MillionSend.Inboxes.Release do
  @moduledoc """
  The result of `MillionSend.Inboxes.Quarantine.release/4`. `trusted_sender` is
  the address added to the allowlist, `nil` unless `trust_sender: true`.
  """
  @type t :: %__MODULE__{}
  defstruct [:object, :inbox_id, :email_id, :released_at, :trusted_sender]
end

defmodule MillionSend.Inboxes.Quarantine do
  @moduledoc """
  Mail an inbox's safety rules held: kept, listed and releasable by a person (a
  MillionSend extension). Inbox-scoped keys get 403.
  """

  alias MillionSend.{Client, Inboxes, Request}
  alias MillionSend.Inboxes.{QuarantinedEmail, Release}

  @doc "`GET /inboxes/:inbox_id/quarantine` — newest first; accepts `limit:`, `after:`, `before:`."
  @spec list(String.t()) :: {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(inbox_id) when is_binary(inbox_id), do: list(MillionSend.client(), inbox_id, [])

  @spec list(Client.t() | String.t(), String.t() | keyword()) ::
          {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(%Client{} = client, inbox_id) when is_binary(inbox_id), do: list(client, inbox_id, [])

  def list(inbox_id, opts) when is_binary(inbox_id) and is_list(opts),
    do: list(MillionSend.client(), inbox_id, opts)

  @spec list(Client.t(), String.t(), keyword()) ::
          {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(%Client{} = client, inbox_id, opts) when is_binary(inbox_id) and is_list(opts) do
    Request.run(client,
      method: :get,
      path: Inboxes.path(inbox_id) <> "/quarantine",
      query: Request.list_query(opts),
      as: {:list, QuarantinedEmail}
    )
  end

  @doc """
  `POST /inboxes/:inbox_id/quarantine/:email_id/release` — option
  `trust_sender: true` also adds the sender's address to the allowlist.
  """
  @spec release(String.t(), String.t()) :: {:ok, Release.t()} | {:error, MillionSend.Error.t()}
  def release(inbox_id, email_id) when is_binary(inbox_id),
    do: release(MillionSend.client(), inbox_id, email_id, [])

  @spec release(Client.t() | String.t(), String.t(), String.t() | keyword()) ::
          {:ok, Release.t()} | {:error, MillionSend.Error.t()}
  def release(%Client{} = client, inbox_id, email_id) when is_binary(inbox_id),
    do: release(client, inbox_id, email_id, [])

  def release(inbox_id, email_id, opts) when is_binary(inbox_id) and is_list(opts),
    do: release(MillionSend.client(), inbox_id, email_id, opts)

  @spec release(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, Release.t()} | {:error, MillionSend.Error.t()}
  def release(%Client{} = client, inbox_id, email_id, opts)
      when is_binary(inbox_id) and is_binary(email_id) and is_list(opts) do
    Request.run(client,
      method: :post,
      path: Inboxes.path(inbox_id) <> "/quarantine/" <> Request.encode(email_id) <> "/release",
      body: if(opts[:trust_sender], do: %{trust_sender: true}, else: %{}),
      as: Release
    )
  end
end

defmodule MillionSend.Inboxes.Label do
  @moduledoc """
  A label of one inbox; `color` is `#RRGGBB`, uppercase. A thread's `labels`
  carry `id`, `name` and `color`. `remove/3` populates `id` plus `deleted`.
  """
  @type t :: %__MODULE__{}
  defstruct [:object, :id, :name, :color, :created_at, :deleted]
end

defmodule MillionSend.Inboxes.Labels do
  @moduledoc """
  An inbox's labels: at most 100, names unique ignoring case. Input maps are
  sent as given: `name` and `color` (`#RRGGBB`; random when omitted on create).
  """

  alias MillionSend.{Client, Inboxes, Request}
  alias MillionSend.Inboxes.Label

  @doc "`GET /inboxes/:inbox_id/labels` — oldest first, not paginated."
  @spec list(Client.t(), String.t()) ::
          {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(client \\ MillionSend.client(), inbox_id) when is_binary(inbox_id) do
    Request.run(client, method: :get, path: path(inbox_id), as: {:list, Label})
  end

  @doc "`POST /inboxes/:inbox_id/labels`"
  @spec create(Client.t(), String.t(), map()) ::
          {:ok, Label.t()} | {:error, MillionSend.Error.t()}
  def create(client \\ MillionSend.client(), inbox_id, params)
      when is_binary(inbox_id) and is_map(params) do
    Request.run(client, method: :post, path: path(inbox_id), body: params, as: Label)
  end

  @doc "`PATCH /inboxes/:inbox_id/labels/:label_id`"
  @spec update(Client.t(), String.t(), String.t(), map()) ::
          {:ok, Label.t()} | {:error, MillionSend.Error.t()}
  def update(client \\ MillionSend.client(), inbox_id, label_id, params)
      when is_binary(inbox_id) and is_binary(label_id) and is_map(params) do
    Request.run(client,
      method: :patch,
      path: path(inbox_id) <> "/" <> Request.encode(label_id),
      body: params,
      as: Label
    )
  end

  @doc "`DELETE /inboxes/:inbox_id/labels/:label_id` — also takes it off every thread."
  @spec remove(Client.t(), String.t(), String.t()) ::
          {:ok, Label.t()} | {:error, MillionSend.Error.t()}
  def remove(client \\ MillionSend.client(), inbox_id, label_id)
      when is_binary(inbox_id) and is_binary(label_id) do
    Request.run(client,
      method: :delete,
      path: path(inbox_id) <> "/" <> Request.encode(label_id),
      as: Label
    )
  end

  defp path(inbox_id), do: Inboxes.path(inbox_id) <> "/labels"
end

defmodule MillionSend.Inboxes.Thread do
  @moduledoc """
  A conversation in one inbox, both directions. `get/3` and `update/4` return
  the summary (`object`, `id`, `subject`, `folder`, `labels`, `read`,
  `quarantined`); list items add the latest message's `from`/`to`/`cc`/`bcc`,
  `message_count`, `has_attachment`, `has_draft` and `received_at`; search
  results add `matched_email_id` and `highlights` (a map of field to fragments
  with `**match**` markers). `folder` is `"inbox" | "archive" | "spam" | "sent" |
  "trash"`. `remove/3` populates `id` plus `deleted`.
  """
  alias MillionSend.Inboxes.Label
  alias MillionSend.Request

  @type t :: %__MODULE__{}
  defstruct [
    :object,
    :id,
    :subject,
    :folder,
    :labels,
    :read,
    :quarantined,
    :from,
    :to,
    :cc,
    :bcc,
    :message_count,
    :has_attachment,
    :has_draft,
    :received_at,
    :matched_email_id,
    :highlights,
    :deleted
  ]

  @doc false
  def cast(map) do
    thread = Request.cast_struct(__MODULE__, map)

    case thread.labels do
      nil -> thread
      labels -> %{thread | labels: Enum.map(labels, &Request.cast_struct(Label, &1))}
    end
  end
end

defmodule MillionSend.Inboxes.Threads do
  @moduledoc """
  An inbox's threads; their emails live in `MillionSend.Inboxes.ThreadEmails`.

  `update/4` params are sent as given: `read` (marks every message), `folder`
  (`"inbox" | "archive" | "spam" | "trash"`; out of trash restores it) and
  `label_id` (applies that label).
  """

  alias MillionSend.{Client, Inboxes, Request}
  alias MillionSend.Inboxes.Thread

  @doc """
  `GET /inboxes/:inbox_id/threads` — most recently active first. Options:
  `folders:` (a list; defaults to `["inbox"]`, or inbox, archive and sent with
  `labels:`), `labels:` (label ids, any-match), `read:`, `limit:`, `after:`,
  `before:` and `include_quarantined: true` (owner views).
  """
  @spec list(String.t()) :: {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(inbox_id) when is_binary(inbox_id), do: list(MillionSend.client(), inbox_id, [])

  @spec list(Client.t() | String.t(), String.t() | keyword()) ::
          {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(%Client{} = client, inbox_id) when is_binary(inbox_id), do: list(client, inbox_id, [])

  def list(inbox_id, opts) when is_binary(inbox_id) and is_list(opts),
    do: list(MillionSend.client(), inbox_id, opts)

  @spec list(Client.t(), String.t(), keyword()) ::
          {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(%Client{} = client, inbox_id, opts) when is_binary(inbox_id) and is_list(opts) do
    Request.run(client,
      method: :get,
      path: path(inbox_id),
      query: list_query(opts),
      as: {:list, &Thread.cast/1}
    )
  end

  @doc """
  `GET /inboxes/:inbox_id/threads/search` — the `list/3` options plus `query:`
  (every word must match; `"a phrase"` and `-word` work), `from:`, `to:`, `cc:`,
  `bcc:` (lists of substrings, any-match), `has_attachment:`, `start_date:` and
  `end_date:` (`YYYY-MM-DD` or ISO 8601). Search covers subject, sender and
  recipients.
  """
  @spec search(String.t()) :: {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def search(inbox_id) when is_binary(inbox_id), do: search(MillionSend.client(), inbox_id, [])

  @spec search(Client.t() | String.t(), String.t() | keyword()) ::
          {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def search(%Client{} = client, inbox_id) when is_binary(inbox_id),
    do: search(client, inbox_id, [])

  def search(inbox_id, opts) when is_binary(inbox_id) and is_list(opts),
    do: search(MillionSend.client(), inbox_id, opts)

  @spec search(Client.t(), String.t(), keyword()) ::
          {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def search(%Client{} = client, inbox_id, opts) when is_binary(inbox_id) and is_list(opts) do
    query =
      list_query(opts) ++
        [
          query: opts[:query],
          from: csv(opts[:from]),
          to: csv(opts[:to]),
          cc: csv(opts[:cc]),
          bcc: csv(opts[:bcc]),
          has_attachment: opts[:has_attachment],
          start_date: opts[:start_date],
          end_date: opts[:end_date]
        ]

    Request.run(client,
      method: :get,
      path: path(inbox_id) <> "/search",
      query: query,
      as: {:list, &Thread.cast/1}
    )
  end

  @doc "`GET /inboxes/:inbox_id/threads/:thread_id` — the summary, without messages."
  @spec get(Client.t(), String.t(), String.t()) ::
          {:ok, Thread.t()} | {:error, MillionSend.Error.t()}
  def get(client \\ MillionSend.client(), inbox_id, thread_id)
      when is_binary(inbox_id) and is_binary(thread_id) do
    Request.run(client, method: :get, path: path(inbox_id, thread_id), as: &Thread.cast/1)
  end

  @doc "`PATCH /inboxes/:inbox_id/threads/:thread_id`"
  @spec update(Client.t(), String.t(), String.t(), map()) ::
          {:ok, Thread.t()} | {:error, MillionSend.Error.t()}
  def update(client \\ MillionSend.client(), inbox_id, thread_id, params)
      when is_binary(inbox_id) and is_binary(thread_id) and is_map(params) do
    Request.run(client,
      method: :patch,
      path: path(inbox_id, thread_id),
      body: params,
      as: &Thread.cast/1
    )
  end

  @doc """
  `DELETE /inboxes/:inbox_id/threads/:thread_id` — moves it to trash, purged
  after 30 days; `deleted` is `false` when it was already there.
  """
  @spec remove(Client.t(), String.t(), String.t()) ::
          {:ok, Thread.t()} | {:error, MillionSend.Error.t()}
  def remove(client \\ MillionSend.client(), inbox_id, thread_id)
      when is_binary(inbox_id) and is_binary(thread_id) do
    Request.run(client, method: :delete, path: path(inbox_id, thread_id), as: &Thread.cast/1)
  end

  @doc false
  def path(inbox_id), do: Inboxes.path(inbox_id) <> "/threads"
  def path(inbox_id, thread_id), do: path(inbox_id) <> "/" <> Request.encode(thread_id)

  defp list_query(opts) do
    Request.list_query(opts) ++
      [
        folders: csv(opts[:folders]),
        labels: csv(opts[:labels]),
        read: opts[:read],
        include_quarantined: if(opts[:include_quarantined], do: true)
      ]
  end

  defp csv(nil), do: nil
  defp csv([]), do: nil
  defp csv(values), do: Enum.join(values, ",")
end

defmodule MillionSend.Inboxes.ThreadEmail do
  @moduledoc """
  One email in an inbox thread, either direction (`direction` is `"inbound" |
  "outbound"`); also the sent email that reply and forward return (`email_id`,
  `thread_id`, `inbox_id`). From `MillionSend.Receiving.reply/4` and
  `forward/4` only `object`, `id`, `thread_id` and `inbox_id` are set.

  Inbound emails carry `extracted_text`, `screening` (a map), `spam_verdict`
  and `virus_verdict`; outbound ones `status` (the latest delivery event).
  `attachments` are `MillionSend.Receiving.Attachment` structs.
  """
  alias MillionSend.Receiving.Attachment

  @type t :: %__MODULE__{}
  defstruct [
    :object,
    :id,
    :direction,
    :from,
    :to,
    :cc,
    :bcc,
    :reply_to,
    :subject,
    :message_id,
    :html,
    :text,
    :attachments,
    :read,
    :received_at,
    :extracted_text,
    :screening,
    :spam_verdict,
    :virus_verdict,
    :status,
    :email_id,
    :thread_id,
    :inbox_id
  ]

  @doc false
  def cast(map) do
    email = MillionSend.Request.cast_struct(__MODULE__, map)
    %{email | attachments: Attachment.cast_list(email.attachments)}
  end
end

defmodule MillionSend.Inboxes.ThreadEmails do
  @moduledoc """
  The emails of one thread, both directions.

  `reply/6` params are sent as given: `html` and/or `text`, `subject`, `cc`,
  `bcc`, `reply_all` and `requires_approval`. `forward/6` takes `to` (required),
  `cc`, `bcc`, `html`/`text` (a note above the quoted original), `subject` and
  `requires_approval`. Both return `{:ok, {:sent, %MillionSend.Inboxes.ThreadEmail{}}}`,
  or `{:ok, {:draft, %MillionSend.Inboxes.Draft{}}}` when the inbox's send rules
  held the message for a person to approve (the API answers 202). Option
  `idempotency_key:` is sent as the `Idempotency-Key` header.
  """

  alias MillionSend.{Client, Request}
  alias MillionSend.Inboxes.{Draft, ThreadEmail, Threads}

  @doc "`GET /inboxes/:inbox_id/threads/:thread_id/emails` — oldest first; `after:` pages to newer."
  @spec list(String.t(), String.t()) ::
          {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(inbox_id, thread_id) when is_binary(inbox_id),
    do: list(MillionSend.client(), inbox_id, thread_id, [])

  @spec list(Client.t() | String.t(), String.t(), String.t() | keyword()) ::
          {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(%Client{} = client, inbox_id, thread_id) when is_binary(inbox_id),
    do: list(client, inbox_id, thread_id, [])

  def list(inbox_id, thread_id, opts) when is_binary(inbox_id) and is_list(opts),
    do: list(MillionSend.client(), inbox_id, thread_id, opts)

  @spec list(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(%Client{} = client, inbox_id, thread_id, opts)
      when is_binary(inbox_id) and is_binary(thread_id) and is_list(opts) do
    Request.run(client,
      method: :get,
      path: Threads.path(inbox_id, thread_id) <> "/emails",
      query: Request.list_query(opts),
      as: {:list, &ThreadEmail.cast/1}
    )
  end

  @doc "`GET /inboxes/:inbox_id/threads/:thread_id/emails/:email_id`"
  @spec get(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, ThreadEmail.t()} | {:error, MillionSend.Error.t()}
  def get(client \\ MillionSend.client(), inbox_id, thread_id, email_id)
      when is_binary(inbox_id) and is_binary(thread_id) and is_binary(email_id) do
    Request.run(client,
      method: :get,
      path: path(inbox_id, thread_id, email_id),
      as: &ThreadEmail.cast/1
    )
  end

  @doc "`POST /inboxes/:inbox_id/threads/:thread_id/emails/:email_id/reply`"
  @spec reply(String.t(), String.t(), String.t(), map()) :: Draft.send_result(ThreadEmail.t())
  def reply(inbox_id, thread_id, email_id, params) when is_binary(inbox_id),
    do: reply(MillionSend.client(), inbox_id, thread_id, email_id, params, [])

  @spec reply(
          Client.t() | String.t(),
          String.t(),
          String.t(),
          String.t() | map(),
          map() | keyword()
        ) ::
          Draft.send_result(ThreadEmail.t())
  def reply(%Client{} = client, inbox_id, thread_id, email_id, params) when is_binary(inbox_id),
    do: reply(client, inbox_id, thread_id, email_id, params, [])

  def reply(inbox_id, thread_id, email_id, params, opts)
      when is_binary(inbox_id) and is_list(opts),
      do: reply(MillionSend.client(), inbox_id, thread_id, email_id, params, opts)

  @spec reply(Client.t(), String.t(), String.t(), String.t(), map(), keyword()) ::
          Draft.send_result(ThreadEmail.t())
  def reply(%Client{} = client, inbox_id, thread_id, email_id, params, opts)
      when is_binary(inbox_id) and is_list(opts) do
    path = path(inbox_id, thread_id, email_id) <> "/reply"
    Draft.send_or_hold(client, path, params, opts, &ThreadEmail.cast/1)
  end

  @doc "`POST /inboxes/:inbox_id/threads/:thread_id/emails/:email_id/forward`"
  @spec forward(String.t(), String.t(), String.t(), map()) :: Draft.send_result(ThreadEmail.t())
  def forward(inbox_id, thread_id, email_id, params) when is_binary(inbox_id),
    do: forward(MillionSend.client(), inbox_id, thread_id, email_id, params, [])

  @spec forward(
          Client.t() | String.t(),
          String.t(),
          String.t(),
          String.t() | map(),
          map() | keyword()
        ) ::
          Draft.send_result(ThreadEmail.t())
  def forward(%Client{} = client, inbox_id, thread_id, email_id, params)
      when is_binary(inbox_id),
      do: forward(client, inbox_id, thread_id, email_id, params, [])

  def forward(inbox_id, thread_id, email_id, params, opts)
      when is_binary(inbox_id) and is_list(opts),
      do: forward(MillionSend.client(), inbox_id, thread_id, email_id, params, opts)

  @spec forward(Client.t(), String.t(), String.t(), String.t(), map(), keyword()) ::
          Draft.send_result(ThreadEmail.t())
  def forward(%Client{} = client, inbox_id, thread_id, email_id, params, opts)
      when is_binary(inbox_id) and is_list(opts) do
    path = path(inbox_id, thread_id, email_id) <> "/forward"
    Draft.send_or_hold(client, path, params, opts, &ThreadEmail.cast/1)
  end

  defp path(inbox_id, thread_id, email_id),
    do: Threads.path(inbox_id, thread_id) <> "/emails/" <> Request.encode(email_id)
end

defmodule MillionSend.Inboxes.Draft do
  @moduledoc """
  A draft in an inbox, including one the send rules hold (`status:
  "pending_approval"`) until a person approves it. `status` is `"draft" |
  "pending_approval" | "sent" | "rejected" | "expired"`; `approval_reasons` says
  why it was held (e.g. `"send_policy"`, `"ramp"`, `"private_code"`). List items
  carry `snippet` instead of `html`/`text`. A draft send's 200 sets only
  `object`, `id`, `thread_id` and `email_id`. `remove/3` populates `id` plus
  `deleted`.
  """
  alias MillionSend.{Client, Request}

  @type t :: %__MODULE__{}

  @typedoc """
  The result of a reply, forward or draft send: `{:sent, struct}` when it went
  out, `{:draft, %Draft{}}` when the inbox's send rules held it (HTTP 202).
  """
  @type send_result(sent) ::
          {:ok, {:sent, sent} | {:draft, t()}} | {:error, MillionSend.Error.t()}

  defstruct [
    :object,
    :id,
    :type,
    :to,
    :cc,
    :bcc,
    :subject,
    :html,
    :text,
    :snippet,
    :thread_id,
    :reply_to_email_id,
    :email_id,
    :created_at,
    :updated_at,
    :status,
    :approval_reasons,
    :forward,
    :decided_by,
    :decided_at,
    :expires_at,
    :deleted
  ]

  @doc false
  @spec send_or_hold(Client.t(), String.t(), map() | nil, keyword(), (map() -> struct())) ::
          send_result(struct())
  def send_or_hold(%Client{} = client, path, body, opts, sent) do
    Request.run(client,
      method: :post,
      path: path,
      body: body,
      idempotency_key: opts[:idempotency_key],
      as: fn
        map, 202 -> {:draft, Request.cast_struct(__MODULE__, map)}
        map, _status -> {:sent, sent.(map)}
      end
    )
  end
end

defmodule MillionSend.Inboxes.Drafts do
  @moduledoc """
  An inbox's drafts, including the ones the send rules hold for approval.

  Input maps are sent as given: `create/3` accepts `to`, `cc`, `bcc` (a string
  or a list), `subject`, `html`, `text`, and for a reply draft both `thread_id`
  and `reply_to_email_id` (a reply draft does not copy recipients). `update/4`
  accepts the same content keys, where `nil` clears one; setting `html` or
  `text` replaces the whole body, so the part left out becomes `nil`.

      {:ok, draft} = MillionSend.Inboxes.Drafts.create(inbox_id, %{to: "ada@example.com", text: "Hi"})

      case MillionSend.Inboxes.Drafts.send(inbox_id, draft.id) do
        {:ok, {:sent, sent}} -> sent.email_id
        {:ok, {:draft, held}} -> held.approval_reasons
        {:error, error} -> error.name
      end
  """

  alias MillionSend.{Client, Inboxes, Request}
  alias MillionSend.Inboxes.Draft

  @doc "`GET /inboxes/:inbox_id/drafts` — unsent drafts, most recently updated first; accepts `limit:`, `after:`, `before:`."
  @spec list(String.t()) :: {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(inbox_id) when is_binary(inbox_id), do: list(MillionSend.client(), inbox_id, [])

  @spec list(Client.t() | String.t(), String.t() | keyword()) ::
          {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(%Client{} = client, inbox_id) when is_binary(inbox_id), do: list(client, inbox_id, [])

  def list(inbox_id, opts) when is_binary(inbox_id) and is_list(opts),
    do: list(MillionSend.client(), inbox_id, opts)

  @spec list(Client.t(), String.t(), keyword()) ::
          {:ok, MillionSend.List.t()} | {:error, MillionSend.Error.t()}
  def list(%Client{} = client, inbox_id, opts) when is_binary(inbox_id) and is_list(opts) do
    Request.run(client,
      method: :get,
      path: path(inbox_id),
      query: Request.list_query(opts),
      as: {:list, Draft}
    )
  end

  @doc "`POST /inboxes/:inbox_id/drafts` — the existing draft when a reply draft already targets that email."
  @spec create(Client.t(), String.t(), map()) ::
          {:ok, Draft.t()} | {:error, MillionSend.Error.t()}
  def create(client \\ MillionSend.client(), inbox_id, params)
      when is_binary(inbox_id) and is_map(params) do
    Request.run(client, method: :post, path: path(inbox_id), body: params, as: Draft)
  end

  @doc "`GET /inboxes/:inbox_id/drafts/:draft_id` — also after it was sent."
  @spec get(Client.t(), String.t(), String.t()) ::
          {:ok, Draft.t()} | {:error, MillionSend.Error.t()}
  def get(client \\ MillionSend.client(), inbox_id, draft_id)
      when is_binary(inbox_id) and is_binary(draft_id) do
    Request.run(client, method: :get, path: path(inbox_id, draft_id), as: Draft)
  end

  @doc "`PATCH /inboxes/:inbox_id/drafts/:draft_id` — 409 once sent or when it changed meanwhile."
  @spec update(Client.t(), String.t(), String.t(), map()) ::
          {:ok, Draft.t()} | {:error, MillionSend.Error.t()}
  def update(client \\ MillionSend.client(), inbox_id, draft_id, params)
      when is_binary(inbox_id) and is_binary(draft_id) and is_map(params) do
    Request.run(client, method: :patch, path: path(inbox_id, draft_id), body: params, as: Draft)
  end

  @doc "`DELETE /inboxes/:inbox_id/drafts/:draft_id`"
  @spec remove(Client.t(), String.t(), String.t()) ::
          {:ok, Draft.t()} | {:error, MillionSend.Error.t()}
  def remove(client \\ MillionSend.client(), inbox_id, draft_id)
      when is_binary(inbox_id) and is_binary(draft_id) do
    Request.run(client, method: :delete, path: path(inbox_id, draft_id), as: Draft)
  end

  @doc """
  `POST /inboxes/:inbox_id/drafts/:draft_id/send` — no body; option
  `idempotency_key:`. Returns `{:ok, {:sent, %Draft{}}}` (with `email_id` and
  `thread_id`) or `{:ok, {:draft, %Draft{}}}` when the send rules hold it. An
  inbox-scoped key sending a pending draft gets 403 `approval_required`.
  """
  @spec send(String.t(), String.t()) :: Draft.send_result(Draft.t())
  def send(inbox_id, draft_id) when is_binary(inbox_id),
    do: send(MillionSend.client(), inbox_id, draft_id, [])

  @spec send(Client.t() | String.t(), String.t(), String.t() | keyword()) ::
          Draft.send_result(Draft.t())
  def send(%Client{} = client, inbox_id, draft_id) when is_binary(inbox_id),
    do: send(client, inbox_id, draft_id, [])

  def send(inbox_id, draft_id, opts) when is_binary(inbox_id) and is_list(opts),
    do: send(MillionSend.client(), inbox_id, draft_id, opts)

  @spec send(Client.t(), String.t(), String.t(), keyword()) :: Draft.send_result(Draft.t())
  def send(%Client{} = client, inbox_id, draft_id, opts)
      when is_binary(inbox_id) and is_binary(draft_id) and is_list(opts) do
    Draft.send_or_hold(
      client,
      path(inbox_id, draft_id) <> "/send",
      nil,
      opts,
      &Request.cast_struct(Draft, &1)
    )
  end

  @doc "`POST /inboxes/:inbox_id/drafts/:draft_id/reject` — approvers only (a MillionSend extension)."
  @spec reject(Client.t(), String.t(), String.t()) ::
          {:ok, Draft.t()} | {:error, MillionSend.Error.t()}
  def reject(client \\ MillionSend.client(), inbox_id, draft_id)
      when is_binary(inbox_id) and is_binary(draft_id) do
    Request.run(client, method: :post, path: path(inbox_id, draft_id) <> "/reject", as: Draft)
  end

  defp path(inbox_id), do: Inboxes.path(inbox_id) <> "/drafts"
  defp path(inbox_id, draft_id), do: path(inbox_id) <> "/" <> Request.encode(draft_id)
end
