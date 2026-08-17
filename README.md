# millionsend

Official Elixir SDK for [MillionSend](https://github.com/MillionSend/millionsend) — a self-hostable, Resend-compatible email API on AWS SES.

The API is wire-compatible with Resend, and this SDK mirrors the shape of
[`resend-elixir`](https://hex.pm/packages/resend), so migrating is mostly a
find-and-replace: swap the module prefix and point `base_url` at your instance.

## Install

```elixir
# mix.exs
def deps do
  [{:millionsend, "~> 0.2"}]
end
```

Requires Elixir 1.15+. HTTP is handled by [Req](https://hex.pm/packages/req).

## Quickstart

```elixir
config :millionsend, MillionSend.Client,
  api_key: System.get_env("MILLIONSEND_API_KEY"),
  base_url: "https://mail.acme.dev"
```

```elixir
case MillionSend.Emails.send(%{
       from: "Acme <onboarding@acme.dev>",
       to: "delivered@resend.dev",
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
- `base_url` defaults to `http://localhost:3001`. MillionSend is self-hosted, so
  **set this to your deployment in production.**
- `user_agent` (optional) appends a suffix after the SDK's own User-Agent token.
- `http_client` (optional) swaps the HTTP layer — any module implementing the
  `MillionSend.HTTP` behaviour (used to stub requests in tests).

Every function accepts an optional leading `client` argument; omit it to use the
configured default.

## Errors

No function raises for an API error — each returns `{:ok, struct}` or
`{:error, %MillionSend.Error{}}`. The error's `name` is a stable snake_case code
you can match on (`"validation_error"`, `"not_found"`, `"restricted_api_key"`,
`"sending_paused"`, …). Client-side and transport failures carry
`status_code: nil`.

```elixir
case MillionSend.Emails.get(id) do
  {:ok, email} -> email
  {:error, %MillionSend.Error{name: "not_found"}} -> :gone
  {:error, error} -> {:error, error.status_code, error.message}
end
```

`MillionSend.Error` is also an exception, so you can `raise`/`Exception.message/1`
it if you prefer to bubble failures up.

## Resources

### Emails

```elixir
MillionSend.Emails.send(payload)                             # POST /emails
MillionSend.Emails.send(payload, idempotency_key: key)       # with idempotency
MillionSend.Emails.get(id)                                   # GET /emails/:id
MillionSend.Emails.cancel(id)                                # POST /emails/:id/cancel (scheduled only)
MillionSend.Emails.send_batch([a, b], idempotency_key: key)  # POST /emails/batch (up to 100)
```

Input maps are snake_case (`:reply_to`, `:scheduled_at`); `:to`/`:cc`/`:bcc`/
`:reply_to` accept a string or a list of strings.

### Contacts

Contacts are team-global — one per email per team (case-insensitive).

```elixir
MillionSend.Contacts.create(%{email: "ada@acme.dev",
                              first_name: "Ada", properties: %{plan: "pro"}})
MillionSend.Contacts.get(%{email: "ada@acme.dev"})     # id or email (email wins)
MillionSend.Contacts.get("contact-uuid")               # bare id works too
MillionSend.Contacts.update(%{id: id, unsubscribed: true, first_name: nil})  # nil clears
MillionSend.Contacts.remove(%{email: "ada@acme.dev"})
MillionSend.Contacts.list(limit: 50, after: cursor)

# Topic subscriptions (granular unsubscribe)
MillionSend.Contacts.update_topics(%{email: "ada@acme.dev",
                                     topics: [%{id: topic_id, subscription: :opt_out}]})
```

### Topics

```elixir
MillionSend.Topics.create(%{name: "Product updates", default_subscription: :opt_in})
MillionSend.Topics.get(id)
MillionSend.Topics.list()      # a plain list — topics are unpaginated
MillionSend.Topics.remove(id)
```

### Broadcasts

```elixir
# Target with segment_id: and/or topic_id:; omit both to send to all contacts.
{:ok, broadcast} = MillionSend.Broadcasts.create(%{
  from: "Acme <news@acme.dev>", subject: "Launch",
  html: "<p>Hi {{{FIRST_NAME|there}}}</p>"
})
MillionSend.Broadcasts.list()
MillionSend.Broadcasts.get(id)
MillionSend.Broadcasts.update(id, %{subject: "Launch 🚀"})              # draft only
MillionSend.Broadcasts.send(id, scheduled_at: "2026-09-01T09:00:00Z")  # omit to send now
MillionSend.Broadcasts.cancel(id)                                      # scheduled only
MillionSend.Broadcasts.remove(id)                                      # draft only
```

### Segments (MillionSend extension)

Dynamic segments are a saved filter over the team's contacts — a MillionSend
superset with no Resend equivalent.

```elixir
MillionSend.Segments.create(%{
  name: "Pro plan",
  filter: %{match: :all, conditions: [%{field: "property:plan", op: "equals", value: "pro"}]}
})
MillionSend.Segments.get(id)   # includes a live contact_count
MillionSend.Segments.list()
MillionSend.Segments.update(id, %{name: "Pro tier"})
MillionSend.Segments.remove(id)
```

## Migrating from Resend

```diff
- {:ok, email} = Resend.Emails.send(%{from: ..., to: ..., subject: ..., html: ...})
+ {:ok, email} = MillionSend.Emails.send(%{from: ..., to: ..., subject: ..., html: ...})
```

```diff
- config :resend, api_key: "re_123"
+ config :millionsend, MillionSend.Client, api_key: "ms_123", base_url: "https://mail.acme.dev"
```

Module names, function names and payloads match. Notes:

- **Domains and API keys** are managed in the MillionSend dashboard, not via the
  API, so there are no `Domains`/`ApiKeys` modules here.
- **No audiences.** Contacts are team-global; drop the `audience_id` from
  `contacts.*` calls. Target broadcasts with a `segment_id` (a dynamic filter)
  and/or a `topic_id` instead.

## Testing against a real instance

The suite is fully mocked. An opt-in end-to-end test runs only when
`MILLIONSEND_API_KEY` is set (and `MILLIONSEND_BASE_URL` if not localhost):

```bash
MILLIONSEND_API_KEY=ms_... MILLIONSEND_BASE_URL=http://localhost:3001 mix test
```

## License

MIT
