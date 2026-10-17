# millionsend

Official Elixir SDK for [MillionSend](https://github.com/MillionSend/millionsend) — a self-hostable, Resend-compatible email API on AWS SES.

The API is wire-compatible with Resend, and this SDK mirrors the shape of
[`resend-elixir`](https://hex.pm/packages/resend), so migrating is mostly a
find-and-replace: swap the module prefix (and, if you self-host, point `base_url`
at your instance).

## Install

```elixir
# mix.exs
def deps do
  [{:millionsend, "~> 0.9"}]
end
```

Requires Elixir 1.15+. HTTP is handled by [Req](https://hex.pm/packages/req).

## Quickstart

```elixir
config :millionsend, MillionSend.Client,
  api_key: System.get_env("MILLIONSEND_API_KEY")
# Self-hosting? Add base_url: "https://mail.acme.dev" to point at your instance.
```

```elixir
case MillionSend.Emails.send(%{
       from: "Acme <onboarding@acme.dev>",
       to: "success@simulator.amazonses.com",
       subject: "Hello from MillionSend",
       html: "<strong>It works!</strong>"
     }) do
  {:ok, email} -> IO.puts("sent #{email.id}")
  {:error, error} -> IO.puts("#{error.name}: #{error.message}")
end
```

## Configuration

Two interchangeable styles, use whichever fits:

```elixir
# 1. Application env — every call works without an explicit client.
config :millionsend, MillionSend.Client,
  api_key: "ms_123",
  base_url: "https://mail.acme.dev"

MillionSend.Emails.get("email-id")

# 2. An explicit client passed as the first argument.
client = MillionSend.client(api_key: "ms_123", base_url: "https://mail.acme.dev")
MillionSend.Emails.get(client, "email-id")
```

Resolution precedence for each option: explicit `MillionSend.client/1` opts →
`config :millionsend, MillionSend.Client` → OS environment
(`MILLIONSEND_API_KEY`, `MILLIONSEND_BASE_URL`) → defaults.

- `api_key` is required; missing everywhere raises `ArgumentError`.
- `base_url` defaults to MillionSend Cloud (`https://api.millionsend.com`), so
  Cloud works with just the key. A self-hosted instance sets its own origin here.
- `allow_insecure_http` (optional, default `false`). Plain `http://` is only accepted
  for loopback hosts (`localhost`, `127.0.0.1`, `::1`); any other `http://` URL raises
  `ArgumentError`, since the API key is sent as a bearer header. Set it to `true` to
  talk to a non-TLS instance elsewhere (e.g. inside a private network).
- `user_agent` (optional) appends a suffix after the SDK's own User-Agent token.
- `http_client` (optional) swaps the HTTP layer — any module implementing the
  `MillionSend.HTTP` behaviour (used to stub requests in tests).

Every function accepts an optional leading `client` argument; omit it to use the
configured default.

## Payloads

Input maps are sent to the API exactly as written — atom or string keys,
snake_case names, and every key you pass reaches the wire (an explicit `nil`
is sent as JSON `null`, which clears a nullable field on update). The API
validates the payload and rejects what it does not accept, so nothing is
silently dropped on the way out.

## Errors

No function raises for an API error — each returns `{:ok, struct}` (the inbox
sends: `{:ok, {:sent, struct}}` or `{:ok, {:draft, draft}}`) or
`{:error, %MillionSend.Error{}}`. The error's `name` is a stable snake_case code
you can match on (`"validation_error"`, `"not_found"`, `"forbidden"`,
`"restricted_api_key"`, `"rate_limit_exceeded"`, `"sending_paused"`, …).
Client-side and transport failures carry `status_code: nil`. `retry_after` is
the response's `retry-after` header in seconds, or `nil` when it has none.
`Emails.send/2` and `send_batch/2` answer a 422
`"all_recipients_suppressed"` when every `to` recipient is on the suppression
list or opted out of the send's `topic_id`. When the suppression list alone
empties `to`, `send/2` also keeps a metadata-only `suppressed` email, which
fires `email.suppressed`; each retry keeps another, even with the same
`idempotency_key:`.

Inboxes add `"inbox_send_policy"` (403, a send the inbox's rules or the shared
domain hold), `"inbox_send_cap_reached"` (429, the inbox's or the team's daily
cap), `"approval_required"` (403), `"email_quarantined"` (403),
`"email_blocked"` (410, a download of an email that carries malware),
`"too_many_waits"` (429, too many concurrent long-polls) and
`"name_review_unavailable"` (503, a name on the shared domain can't be reviewed
yet).

```elixir
case MillionSend.Emails.get(id) do
  {:ok, email} -> email
  {:error, %MillionSend.Error{name: "not_found"}} -> :gone
  {:error, error} -> {:error, error.status_code, error.message}
end
```

`MillionSend.Error` is also an exception, so you can `raise`/`Exception.message/1`
it if you prefer to bubble failures up.

### Retries

The SDK never retries on its own. Worth retrying after `retry_after` seconds:
503 `"name_review_unavailable"`, 429 `"too_many_waits"`, and 429
`"rate_limit_exceeded"` when `retry_after` is 60 or less (the per-minute
limits). Not worth retrying in the same process: 429 `"inbox_send_cap_reached"`
and the daily name-review budget (429 `"rate_limit_exceeded"` with a
`retry_after` that runs to the next UTC midnight), and any 403, 404, 409 or 422.
An unknown route answers 404 `"not_found"` (`"application_error"` from servers
before v0.13.0).

Resend a send with the same `idempotency_key:`: a batch the API already
accepted gets its stored response back. A held draft (`{:ok, {:draft, draft}}`)
is not a failure; never resend it. `Inboxes.create/2` takes no idempotency key:
after a 429 or 503 nothing was created, but after a timeout a resend can create
a second inbox. With a chosen `username`, a 409 on the resend usually means the
first attempt succeeded: read it with `Inboxes.get/2` by its address.

## Lists

List functions take `limit:`, `after:` and `before:` (keyset cursors) and
return a `MillionSend.List` with `data` and `has_more`. Lists run newest first
(MillionSend v0.13.0 and later): `after:` takes the last id of a page and pages
toward older items, `before:` takes the first id and pages toward newer ones,
and `has_more` refers to that direction. Threads sort by last activity, drafts
by last update, a thread's emails run oldest first, and labels and topics are
not paginated.

```elixir
# Incremental sync: page toward newer items, starting from the newest id you stored
def sync(before) do
  {:ok, page} = MillionSend.Emails.list(before: before, limit: 100)
  save(page.data)                         # newest first within the page
  if page.has_more, do: sync(hd(page.data).id), else: :ok
end
```

A cursor whose item was deleted answers 422 `"validation_error"` (404
`"not_found"` on the inbox lists): start again without a cursor and stop at the
ids you already have.

## Resources

### Emails

```elixir
MillionSend.Emails.send(%{
  from: "Acme <onboarding@acme.dev>",
  to: ["ada@acme.dev"],                       # string or list; same for cc/bcc/reply_to
  subject: "Hello",
  html: "<p>Hi</p>", text: "Hi",
  reply_to: "support@acme.dev",
  scheduled_at: "in 2 hours",                 # ISO 8601 or relative
  tags: [%{name: "campaign", value: "welcome"}],
  topic_id: topic_id,                         # opted-out recipients are skipped
  attachments: [%{filename: "hi.txt", content: Base.encode64("hi"), content_type: "text/plain"}],
  headers: %{"X-Entity-Ref-ID" => "42"}
}, idempotency_key: key)                      # POST /emails

MillionSend.Emails.get(id)                    # GET /emails/:id (includes score)
MillionSend.Emails.list(limit: 50, after: cursor)  # GET /emails
MillionSend.Emails.update(id, scheduled_at: "in 1 day")  # PATCH /emails/:id (scheduled only)
MillionSend.Emails.cancel(id)                 # POST /emails/:id/cancel (scheduled only)
MillionSend.Emails.remove(id)                 # DELETE /emails/:id
MillionSend.Emails.get_insights(id)           # GET /emails/:id/insights
```

`subject` takes up to 998 characters. A `to`, `cc` or `bcc` address on a domain
that can never receive mail (`example.com`, `.test`, `.invalid`, `.localhost`,
a TLD that doesn't exist, …) answers 422 `"validation_error"`; to test sending
without emailing anyone, use `success@simulator.amazonses.com`. An inbox's
address on the shared domain can be the `from` too, under the rules in
[Sending from the shared domain](#sending-from-the-shared-domain).

Batches take up to 100 emails. Strict validation (the default) is
all-or-nothing and returns a plain list; `batch_validation: :permissive` sends
the `x-batch-validation` header, writes the valid subset and returns a
`MillionSend.Emails.BatchResponse` with the rejected items in `errors`:

```elixir
{:ok, [%{id: _}, %{id: _}]} =
  MillionSend.Emails.send_batch([a, b], idempotency_key: key)       # POST /emails/batch

{:ok, %MillionSend.Emails.BatchResponse{data: sent, errors: errors}} =
  MillionSend.Emails.send_batch([a, b], batch_validation: :permissive)
errors  # [%MillionSend.BatchError{index: 1, message: "..."}]
```

Batch items never send from the shared domain: a strict batch fails with 403
`"inbox_send_policy"` (the message starts with `emails.<index>: `), a
permissive one lists the item in `errors`.

### Contacts

Contacts are team-global — one per email per team (case-insensitive) — and
addressable by id or email.

```elixir
MillionSend.Contacts.create(%{
  email: "ada@acme.dev", first_name: "Ada", last_name: "Lovelace",
  unsubscribed: false, properties: %{plan: "pro"},
  segments: [%{id: segment_id}],
  topics: [%{id: topic_id, subscription: :opt_in}]
})
MillionSend.Contacts.get(%{email: "ada@acme.dev"})     # id or email (email wins)
MillionSend.Contacts.get("contact-uuid")               # bare id works too
MillionSend.Contacts.update(%{id: id, unsubscribed: true, first_name: nil})  # nil clears
MillionSend.Contacts.remove(%{email: "ada@acme.dev"})               # emails stay in the send log
MillionSend.Contacts.remove(%{email: "ada@acme.dev"}, erase: true)  # also scrubs the address from history and logs (GDPR/LGPD)
MillionSend.Contacts.list(limit: 50, after: cursor)
MillionSend.Contacts.list(include: [:properties, :topics])   # ?include= attaches both to every item
MillionSend.Contacts.batch_remove(%{emails: ["a@acme.dev"]})   # or %{ids: [...]}; up to 1000; emails stay in the send log
MillionSend.Contacts.batch_remove(%{ids: [id], erase: true})    # also scrubs each address from history and logs

# Bulk read (up to 1000) by id or email in one request; unknown entries land in
# missing instead of failing the call.
{:ok, %MillionSend.Contacts.BatchGetResponse{data: contacts, missing: missing}} =
  MillionSend.Contacts.batch_get(["contact-uuid", %{email: "b@acme.dev"}], include: [:topics])
contacts  # [%MillionSend.Contacts.Contact{id: ..., topics: [%MillionSend.Contacts.TopicSubscription{}, ...]}]
missing   # [%MillionSend.Contacts.BatchGetResponse.Missing{index: 1, email: "b@acme.dev"}]

# Bulk create (up to 1000). on_conflict: :error (default) | :skip | :upsert;
# batch_validation: :strict (default) | :permissive.
{:ok, %MillionSend.Contacts.BatchResponse{data: items, counts: counts, errors: errors}} =
  MillionSend.Contacts.create_batch([%{email: "a@acme.dev"}, %{email: "b@acme.dev"}],
                                    on_conflict: :upsert, batch_validation: :permissive)
items   # [%MillionSend.Contacts.BatchResponse.Item{index: 0, id: ..., status: "created"}, ...]
counts  # %{created: 2, updated: 0, skipped: 0, failed: 0}
errors  # permissive only, as strict mode would answer each item:
        # [%MillionSend.BatchError{index: 1, status_code: 422, name: "validation_error", message: ...}]

# Segment membership
MillionSend.Contacts.add_to_segment(%{email: "ada@acme.dev"}, segment_id)
MillionSend.Contacts.remove_from_segment(contact_id, segment_id)

# Topic subscriptions (granular unsubscribe)
MillionSend.Contacts.update_topics(%{email: "ada@acme.dev",
                                     topics: [%{id: topic_id, subscription: :opt_out}]})
{:ok, %MillionSend.List{data: topics}} = MillionSend.Contacts.list_topics(%{email: "ada@acme.dev"})
topics  # [%MillionSend.Contacts.TopicSubscription{id: ..., name: ..., subscription: "opt_out", explicit: true}, ...]
        # explicit: false means the contact inherits the topic's default_subscription

# Hosted preference page (the one the contact's unsubscribe links open)
{:ok, link} = MillionSend.Contacts.preferences_link(%{email: "ada@acme.dev"})
link.url   # signed, contact-scoped, no expiry — hand it only to the contact
```

### Contact properties

```elixir
MillionSend.ContactProperties.create(%{key: "plan", type: :string, fallback_value: "free"})
MillionSend.ContactProperties.list()
MillionSend.ContactProperties.get(id)
MillionSend.ContactProperties.update(id, %{fallback_value: nil})   # nil clears
MillionSend.ContactProperties.remove(id)
```

### Topics

```elixir
MillionSend.Topics.create(%{name: "Product updates", default_subscription: :opt_in,
                            visibility: :public})
MillionSend.Topics.get(id)
MillionSend.Topics.list()      # a plain list — topics are unpaginated
MillionSend.Topics.update(id, %{description: "Monthly digest"})
MillionSend.Topics.remove(id)
```

### Broadcasts

```elixir
# Target with segment_id: and/or topic_id:; omit both to send to all contacts.
{:ok, broadcast} = MillionSend.Broadcasts.create(%{
  name: "Launch", from: "Acme <news@acme.dev>", subject: "Launch",
  html: "<p>Hi {{{FIRST_NAME|there}}}</p>", preview_text: "It's here",
  reply_to: "hello@acme.dev", topic_id: topic_id
})
MillionSend.Broadcasts.create(%{..., send: true, scheduled_at: "in 1 hour"})  # create and schedule
MillionSend.Broadcasts.list()
MillionSend.Broadcasts.get(id)
MillionSend.Broadcasts.update(id, %{subject: "Launch 🚀", topic_id: nil})  # draft only; nil clears
MillionSend.Broadcasts.send(id, scheduled_at: "2026-09-01T09:00:00Z")  # omit to send now
MillionSend.Broadcasts.cancel(id)                                      # scheduled only
MillionSend.Broadcasts.remove(id)                                      # draft only
```

`subject` takes up to 998 characters. A broadcast never sends from the shared
domain: `create/2` with `send: true` and `send/3` answer 403
`"inbox_send_policy"`.

### Segments

A segment with a `filter` is dynamic — a saved query over the team's contacts
(a MillionSend extension; Resend segments are static lists). Without a filter
it is a plain list you add contacts to.

```elixir
MillionSend.Segments.create(%{
  name: "Pro plan",
  filter: %{match: :all, conditions: [%{field: "property:plan", op: "equals", value: "pro"}]}
})
MillionSend.Segments.get(id)   # includes a live contact_count
MillionSend.Segments.list()
MillionSend.Segments.list_contacts(id, limit: 50, include: [:properties])
MillionSend.Segments.update(id, %{name: "Pro tier"})
MillionSend.Segments.remove(id)
```

### Suppressions

Addresses that are never sent to. Entries come from bounces, complaints and
unsubscribes, or are added here; `origin` is `bounce | complaint | manual |
unsubscribe`.

```elixir
MillionSend.Suppressions.create(%{email: "gone@example.com", origin: :manual})
MillionSend.Suppressions.get("gone@example.com")           # id or email
MillionSend.Suppressions.list(origin: :bounce, limit: 50)
MillionSend.Suppressions.remove(id)
MillionSend.Suppressions.batch_add(["a@example.com", "b@example.com"], origin: :unsubscribe)
MillionSend.Suppressions.batch_remove(%{emails: ["a@example.com"]})   # or %{ids: [...]}
```

### Receiving

Mail received at your receiving domains and inboxes. Everything in a received
email was written by its sender, so show its HTML only in a sandbox.

```elixir
{:ok, page} = MillionSend.Receiving.list(inbox_id: inbox_id, from: "acme.dev", limit: 20)  # newest first
{:ok, email} = MillionSend.Receiving.get(id)          # html_format: "cid" keeps cid: references
email.extracted_text                                  # the reply without quotes, signature or hidden text
email.screening["sender_trust"]                       # "owner", "allowlisted", "known_thread", "external", …
email.extracted["code"]                               # a verification code, when one was found

# Long-poll: returns as soon as matching mail arrives (or an empty page after 30 s)
{:ok, page} = MillionSend.Receiving.list(inbox_id: inbox_id, wait: 30)
page.held                                             # matching mail held in quarantine, ids only

case MillionSend.Receiving.reply(id, %{text: "Thanks, confirmed."}, idempotency_key: "reply-#{id}") do
  {:ok, {:sent, sent}} -> sent.thread_id
  {:ok, {:draft, draft}} -> draft.approval_reasons    # held for a person to approve (HTTP 202)
  {:error, error} -> error.name
end

MillionSend.Receiving.forward(id, %{to: "ops@acme.dev", mode: "attachment"})
MillionSend.Receiving.remove(id)                      # erase now
MillionSend.Receiving.Attachments.list(id)            # signed download links, valid one hour
MillionSend.Receiving.Attachments.get(id, attachment_id)
```

Held mail is invisible to inbox-scoped keys: a detail read answers 403
`email_quarantined`. For full-access keys, `include_quarantined: true` lists it
too and `quarantined: true` lists it alone.
With `wait:` the SDK raises the HTTP receive timeout to cover the wait.
`unread:` needs `inbox_id:` with a team key; an inbox-scoped key reads its own
inbox. An `inbox_id:` that doesn't exist answers 404 `"not_found"` at once, even
with `wait:`.

### Inboxes

An inbox is one address that receives mail, read by an agent (`kind: "agent"`,
the default) or by people (`"human"`), with threads in both directions. The
paths mirror Resend's Inboxes API; `kind`, `shared`, `expires_at`, safety,
quarantine and codes are MillionSend extensions. Folder, verdict, kind and
status values are plain strings, so new server values never break decoding.

```elixir
alias MillionSend.Inboxes

{:ok, inbox} = Inboxes.create(%{name: "Signup bot",       # no email_address: an address on the shared domain
                                username: "signup-bot",   # signup-bot@<team>.<shared domain>; omit it for a random one
                                expires_in: "24h",        # "1h" to "365d"; omitted or nil, it never expires
                                safety: %{accept_from: "anyone"}})
Inboxes.create(%{domain_id: domain_id, username: "orders"})  # a Domains.list/1 row: orders@ that domain
Inboxes.list(kind: "agent")
Inboxes.get("bot@acme.dev")                           # by id or address
Inboxes.update(inbox.id, %{expires_in: nil})          # nil: never expires
Inboxes.remove(inbox.id)

# Verification codes and sign-in links (links are never fetched)
{:ok, code} = Inboxes.Codes.latest(inbox_id, from: "github.com", wait: 30)
code.status                                           # "found" | "none" | "ambiguous" | "timeout"
# The next sign-in: only a code received after the one already used
Inboxes.Codes.latest(inbox_id, since: code.received_at, wait: 30)

# Safety rules (inbox-scoped keys can read them, never change them)
Inboxes.Safety.get(inbox_id)
Inboxes.Safety.update(inbox_id, %{accept_from: "allowlist", allowlist: ["*@partner.dev"], send_cap: 100})

# Quarantine: held mail is kept and listed until a person releases it
Inboxes.Quarantine.list(inbox_id)
Inboxes.Quarantine.release(inbox_id, email_id, trust_sender: true)   # also allowlists the sender

# Threads and their emails
Inboxes.Threads.list(inbox_id, folders: ["inbox", "archive"], read: false)
Inboxes.Threads.list(inbox_id, include_quarantined: true)   # owner views: a quarantined count per thread
Inboxes.Threads.search(inbox_id, query: "invoice -draft", from: ["acme"])
Inboxes.Threads.get(inbox_id, thread_id)
Inboxes.Threads.update(inbox_id, thread_id, %{read: true, folder: "archive"})
Inboxes.Threads.remove(inbox_id, thread_id)           # to trash, purged after 30 days
Inboxes.ThreadEmails.list(inbox_id, thread_id)        # oldest first
Inboxes.ThreadEmails.get(inbox_id, thread_id, email_id)
Inboxes.ThreadEmails.reply(inbox_id, thread_id, email_id, %{text: "On it"})
Inboxes.ThreadEmails.forward(inbox_id, thread_id, email_id, %{to: "ops@acme.dev"})

# Labels
{:ok, label} = Inboxes.Labels.create(inbox_id, %{name: "Billing"})
Inboxes.Labels.list(inbox_id)
Inboxes.Labels.update(inbox_id, label.id, %{color: "#FF8800"})
Inboxes.Labels.remove(inbox_id, label.id)

# Drafts, including the ones the send rules hold for approval
{:ok, draft} = Inboxes.Drafts.create(inbox_id, %{to: "ada@acme.dev", subject: "Hello", text: "Hi Ada"})
Inboxes.Drafts.list(inbox_id)
Inboxes.Drafts.get(inbox_id, draft.id)
Inboxes.Drafts.update(inbox_id, draft.id, %{subject: nil})   # nil clears
Inboxes.Drafts.send(inbox_id, draft.id)               # {:ok, {:sent, draft}} | {:ok, {:draft, held}}
Inboxes.Drafts.reject(inbox_id, draft.id)             # approvers only
Inboxes.Drafts.remove(inbox_id, draft.id)
```

Reply, forward and draft send return `{:ok, {:sent, struct}}`, or
`{:ok, {:draft, %MillionSend.Inboxes.Draft{}}}` when the inbox's send rules held
the message for a person to approve (the API's 202). An agent's reply to a
Reply-To at another organization is held that way too, with
`"reply_to_redirect"` among its `approval_reasons`. An inbox-scoped key
sending a pending draft gets 403 `approval_required`. Hosted agent settings
(`/inboxes/:id/agent`) are not exposed: MillionSend runs no agent of its own.

An inbox never expires unless `expires_in` says so, and its `name` takes up to
320 characters. `domain_id` takes a `Domains.list/1` row instead of
`email_address`: the `shared: true` row works like leaving both out, and one of
your own domains needs a `username`.

On the shared domain, an inbox unused for 90 days (no mail in or out, no API
call on it) is deleted, which fires `inbox.expired`, then `inbox.deleted`. A
chosen `username` or `from_name` there is reviewed first: reserved names
(`postmaster`, `admin`, `support`, `noreply`, …), a `fwd-` prefix and
look-alikes of brands answer 422, a username in use 409, and 429 means today's
review budget is spent. 503 `"name_review_unavailable"` means try again after
`retry_after` seconds: the review is down, or the team's new subdomain still
waits for its own, and then every shared or forwarding create gets it. Safety
rules differ there too: `send_policy: "allowlist"` answers 422, and so does
`"open"` unless the team's `sending_mode` is `"open"`; `owner_addresses` don't
make senders trusted; `forward_to` takes team members only.

#### Sending from the shared domain

What the team's shared addresses may send is the `sending_mode` of the
`shared: true` row of `Domains.list/1`: `"open"` starts conversations,
`"reply_only"` only answers inside a thread to its own correspondents, and
`"receive_only"` sends nothing. The same answers come back from
`Emails.send/2`, replies, forwards and drafts:

- 403 `"inbox_send_policy"`: the mode doesn't allow this send (or the inbox's
  name looks like a brand, which only replies even under `"open"`);
- 429 `"inbox_send_cap_reached"`: the team's daily cap for the shared domain,
  with a `retry_after` that runs to the next UTC midnight;
- 422 `"validation_error"`: more than 10 distinct recipients across `to`, `cc`
  and `bcc`.

`Emails.send/2` takes a shared address in `"open"` mode only: the inbox's exact
`email_address` (no +tag), a display name left out or equal to its
`from_name`, and no `reply_to`, `attachments`, `headers` or `scheduled_at`. A
key restricted to a domain gets 403 `"restricted_api_key"`. Batch items and
broadcasts never send from the shared domain. Match on `name` and
`status_code`; the messages may change.

### Domains

```elixir
{:ok, domain} = MillionSend.Domains.create(%{name: "acme.dev", region: "us-east-1",
                                             open_tracking: true, tracking_subdomain: "links"})
domain.records   # [%MillionSend.Domains.Domain.Record{record: "DKIM", name: ..., value: ...}, ...]
MillionSend.Domains.list()
MillionSend.Domains.get(id)
MillionSend.Domains.verify(id)
MillionSend.Domains.update(id, %{click_tracking: true, tracking_subdomain: nil})  # nil clears
MillionSend.Domains.update(id, %{receiving_catch_all: true})   # paid plans on Cloud
MillionSend.Domains.remove(id)
```

`receiving_catch_all`: on, mail to addresses without an inbox lands in the
received list; off, those addresses are refused at SMTP time.

On an instance with a shared inbox domain, the team's subdomain of it is the
last row of `Domains.list/1` (`shared: true`; MillionSend v0.14.0 and later).
It is verified, has no DNS records, and its id is the `domain_id` of the team's
shared inboxes. Its `sending_mode` (`"open"`, `"reply_only"` or
`"receive_only"`) says what those inboxes may send, and `sending_mode_reason`
(`"plan"` or `"instance"`, `nil` under `"open"`) why it is held below
`"open"`. It is read-only: `update/3`, `verify/2` and `remove/2` answer 403
`"forbidden"`, and an API key can't be restricted to it. It comes after every
own domain whatever its `created_at`, alone on the next page when they exactly
fill one. A team whose new subdomain still waits for its name review has no
such row yet. Older servers send no `shared`, which reads as `false`.

It sends only from its inboxes' own addresses, so leave it out when picking a
domain to send from:

```elixir
{:ok, %{data: domains}} = MillionSend.Domains.list(limit: 100)
sender = Enum.find(domains, &(&1.status == "verified" and not &1.shared))
```

### API keys

```elixir
{:ok, key} = MillionSend.ApiKeys.create(%{name: "ci", permission: :sending_access, domain_id: id})
key.token        # shown once — store it
MillionSend.ApiKeys.list()
MillionSend.ApiKeys.remove(id)

# A key restricted to one inbox: it reads that inbox and sends from its address only
MillionSend.ApiKeys.create(%{name: "support-agent", inbox_id: inbox_id})
```

`domain_id` takes one of your own domains: the `shared: true` row of
`Domains.list/1` answers 422 `"validation_error"`.

### Webhooks

```elixir
{:ok, hook} = MillionSend.Webhooks.create(%{
  endpoint: "https://acme.dev/hooks/email",
  events: ["email.delivered", "email.bounced", "email.complained"]
})
hook.signing_secret
MillionSend.Webhooks.list()
MillionSend.Webhooks.get(id)                 # includes signing_secret and previous_secret_expires_at
MillionSend.Webhooks.update(id, %{status: :disabled})
MillionSend.Webhooks.remove(id)

# Rotate the signing secret. For overlap_hours (0..72) deliveries carry both
# signatures, so the receiver can switch without a gap. Pass signing_secret:
# to install your own whsec_ value instead of a minted one.
{:ok, rotated} = MillionSend.Webhooks.rotate(id, overlap_hours: 24)
rotated.signing_secret
rotated.previous_secret_expires_at           # nil when overlap_hours: 0
```

Events include `email.*`, `deliverability.*`, `quota.*`, `contact.*`
(`created`, `updated`, `deleted`, `unsubscribed`, `resubscribed`,
`topic_opt_in`, `topic_opt_out`) and `suppression.*` (`added`, `removed`).

`email.scheduled`, `email.failed` and `email.suppressed` need MillionSend
v0.15.1 or later; an older server refuses a webhook naming them with 422
`"validation_error"`. `email.failed` says why in `data.failed.reason`, and
`email.suppressed` in `data.suppressed` (`type`, `message`, `reason`); treat
their values as open sets. `suppression.added` and `suppression.removed` carry
`data.source_id`, the email whose bounce or complaint created the entry (`nil`
otherwise).

`email.prefetched` and the inbox events (`inbox.created|updated|deleted|expired`,
`inbox.thread.created|folder.updated|labels.updated`,
`inbox.email.received|sent|quarantined`, `inbox.draft.created|updated|sent|deleted`)
reach only endpoints that name them; an endpoint subscribed to all events skips
them, though it does get `email.received`. `inbox_ids: [...]` narrows the inbox
events and `email.received` to some inboxes; `inbox_ids: nil` on update removes
the filter. Inbox events from sends made in the dashboard carry
`data.source: "dashboard"`.

### Templates

Every member function takes the template id or its `alias`.

```elixir
MillionSend.Templates.create(%{name: "Welcome", alias: "welcome", subject: "Hi!",
                               html: "<p>Hi</p>", text: "Hi"})
MillionSend.Templates.list()
MillionSend.Templates.get("welcome")
MillionSend.Templates.update("welcome", %{subject: nil})   # nil clears subject/text/alias
MillionSend.Templates.duplicate("welcome")
MillionSend.Templates.publish("welcome")     # no-op kept for compatibility: templates publish on write
MillionSend.Templates.remove("welcome")
```

### Deliverability (MillionSend extension)

Deliverability scores are 0–10 with one decimal. `MillionSend.Emails.get/2`
returns the email's `score` (`nil` when no insights exist);
`get_insights/2` returns the full per-email report (a `"not_found"` error until
insights exist); `MillionSend.Deliverability.get/1` returns the account-level
score over the trailing window (`nil` scores until there is enough data).

```elixir
{:ok, insights} = MillionSend.Emails.get_insights(id)  # GET /emails/:id/insights
insights.score          # 8.5
insights.band           # "excellent" | "good" | "needs_attention" | "at_risk"
insights.checks         # [%MillionSend.Emails.Insights.Check{id: ..., severity: ..., status: ..., penalty: ..., detail: ...}]

{:ok, report} = MillionSend.Deliverability.get()       # GET /deliverability
report.score            # 8.7 (nil until enough data)
report.guardrail_status # "ok" | "warning" | "paused"
```

### Usage (MillionSend extension)

```elixir
{:ok, usage} = MillionSend.Usage.get()      # GET /usage
usage.plan                                  # "free" | "pro" | "scale" | nil (self-hosted)
usage.limits["emails_per_day"]              # nil = unlimited / self-hosted
usage.today["emails_sent"]
```

## Migrating from Resend

```diff
- {:ok, email} = Resend.Emails.send(%{from: ..., to: ..., subject: ..., html: ...})
+ {:ok, email} = MillionSend.Emails.send(%{from: ..., to: ..., subject: ..., html: ...})
```

```diff
- config :resend, api_key: "re_123"
+ config :millionsend, MillionSend.Client, api_key: "ms_123"   # self-hosted: add base_url: "https://mail.acme.dev"
```

Module names, function names and payloads match. Notes:

- **No audiences.** Contacts are team-global; drop the `audience_id` from
  `contacts.*` calls. The `/audiences/...` compatibility routes are not part of
  this SDK. Target broadcasts with a `segment_id` and/or a `topic_id` instead.
- **Segment filters, deliverability insights and usage** are MillionSend
  extensions with no Resend counterpart, as are, on received mail and inboxes,
  the long-poll `wait:`, received-mail reply/forward/remove, inbox safety, codes,
  quarantine, draft reject, the `username` and `domain_id` of `Inboxes.create/2`
  and the extension fields. So is `MillionSend.Error`'s `retry_after`.
- `Templates.publish/2` is a no-op: templates are published on every write.

## MillionSend versions

Each feature needs this MillionSend version or later. Older servers answer 404
on paths they lack and ignore options they don't know, so an inbox created with
`username` or `domain_id` on one can get another address: check its
`email_address`.

| MillionSend | Features |
|---|---|
| v0.10.0 | `MillionSend.Inboxes`; the receiving long-poll, inbox filters, reply and forward |
| v0.11.0 | 422 for recipients that can never receive mail; a batch `idempotency_key` replayed before validation |
| v0.12.0 | `username`; inboxes that never expire by default; sends from the shared domain under its mode; `"name_review_unavailable"`; `status_code` and `name` on contacts batch errors |
| v0.13.0 | newest-first lists; `since:` on `Inboxes.Codes.latest/3`; `quarantined` on thread items; inbox names up to 320 characters; `unread:` with an inbox-scoped key; a JSON 404 for unknown routes |
| v0.14.0 | `shared`, `sending_mode` and `sending_mode_reason` on domains; `domain_id` on `Inboxes.create/2`; `subject` up to 998 characters |
| v0.15.1 | `email.scheduled`, `email.failed` and `email.suppressed` webhook events; `source_id` on `suppression.added` and `suppression.removed`; the `suppressed` email kept for an all-suppressed `Emails.send/2` |

## Testing against a real instance

The suite is fully mocked. An opt-in end-to-end test runs only when
`MILLIONSEND_API_KEY` is set (and `MILLIONSEND_BASE_URL` for a self-hosted instance):

```bash
MILLIONSEND_API_KEY=ms_... MILLIONSEND_BASE_URL=http://localhost:3001 mix test
```

## License

MIT
