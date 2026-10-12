defmodule MillionSend.InboxesTest do
  use ExUnit.Case, async: true

  import MillionSend.Test.Helpers

  alias MillionSend.Inboxes
  alias MillionSend.Inboxes.{Draft, Inbox, Label, Thread, ThreadEmail}
  alias MillionSend.Receiving
  alias MillionSend.Receiving.{Attachment, EmailList, ReceivedEmail}

  setup do
    {:ok, client: client()}
  end

  @received %{
    "object" => "email",
    "id" => "r1",
    "to" => ["bot@x.dev"],
    "from" => "ada@y.dev",
    "created_at" => "2026-10-12T10:00:00.000Z",
    "subject" => "Your code",
    "bcc" => [],
    "cc" => [],
    "reply_to" => [],
    "received_for" => ["bot@x.dev"],
    "message_id" => "<m1@y.dev>",
    "attachments" => [
      %{
        "id" => "a1",
        "filename" => "a.pdf",
        "content_type" => "application/pdf",
        "content_id" => nil,
        "content_disposition" => "attachment",
        "size" => 42
      }
    ],
    "html" => "<p>482913</p>",
    "html_format" => "cid",
    "text" => "482913",
    "headers" => %{"from" => "Ada <ada@y.dev>"},
    "authentication" => %{"spf" => "pass", "dkim" => "gray", "dmarc" => "pass"},
    "raw" => %{
      "download_url" => "https://api.x.dev/raw/r1",
      "expires_at" => "2026-10-12T11:00:00Z"
    },
    "inbox_id" => "i1",
    "thread_id" => "t1",
    "inboxes" => [%{"inbox_id" => "i1", "thread_id" => "t1", "verdict" => "clean"}],
    "screening" => %{
      "verdict" => "clean",
      "sender_trust" => "a_tier_from_a_newer_server",
      "quarantine_reason" => nil,
      "reasons" => ["targets_agent"],
      "injection_score" => 3,
      "phishing_score" => nil,
      "hidden_text_removed" => true
    },
    "spam_verdict" => "pass",
    "spam_score" => 4,
    "virus_verdict" => "pass",
    "virus_signature" => nil,
    "extracted_text" => "Your code is 482913",
    "extracted" => %{
      "kinds" => ["code"],
      "code" => "482913",
      "link" => nil,
      "link_domain_matches_sender" => nil,
      "ambiguous" => false
    },
    "read" => false,
    "a_field_from_a_newer_server" => %{"x" => 1}
  }

  @draft %{
    "object" => "inbox_draft",
    "id" => "d1",
    "type" => "reply",
    "to" => ["ada@y.dev"],
    "cc" => [],
    "bcc" => [],
    "subject" => "Re: Hi",
    "html" => nil,
    "text" => "Thanks",
    "thread_id" => "t1",
    "reply_to_email_id" => "r1",
    "email_id" => nil,
    "created_at" => "2026-10-12T10:00:00.000Z",
    "updated_at" => "2026-10-12T10:00:00.000Z",
    "status" => "pending_approval",
    "approval_reasons" => ["send_policy", "ramp"],
    "forward" => false,
    "decided_by" => nil,
    "decided_at" => nil,
    "expires_at" => "2026-10-19T10:00:00.000Z"
  }

  describe "receiving" do
    test "list carries every filter, the long-poll timeout and the held ids", %{client: c} do
      stub_json(%{
        "object" => "list",
        "has_more" => false,
        "data" => [@received],
        "held" => [
          %{"id" => "r2", "inbox_id" => "i1", "reason" => "not_allowlisted", "created_at" => "x"}
        ]
      })

      assert {:ok, %EmailList{data: [%ReceivedEmail{} = email], held: [held]}} =
               Receiving.list(c,
                 limit: 5,
                 after: "r0",
                 wait: 20,
                 since: "2026-10-12T10:00:00Z",
                 inbox_id: "i1",
                 to: "bot@x.dev",
                 from: "y.dev",
                 subject_contains: "code",
                 unread: true,
                 include_quarantined: true
               )

      assert req_method() == :get and req_path() == "/emails/receiving"

      assert req_query() ==
               "limit=5&after=r0&wait=20&since=2026-10-12T10%3A00%3A00Z&inbox_id=i1" <>
                 "&to=bot%40x.dev&from=y.dev&subject_contains=code&unread=true" <>
                 "&include_quarantined=true"

      assert last_request().receive_timeout == 35_000
      assert held["reason"] == "not_allowlisted"
      assert email.screening["sender_trust"] == "a_tier_from_a_newer_server"
      assert [%Attachment{size: 42, content_disposition: "attachment"}] = email.attachments

      stub_json(%{"object" => "list", "has_more" => false, "data" => []})
      assert {:ok, %EmailList{data: [], held: nil}} = Receiving.list(c)
      assert req_query() == nil
      refute Map.has_key?(last_request(), :receive_timeout)

      assert {:ok, _} = Receiving.list(c, include_quarantined: false, unread: false)
      assert req_query() == "unread=false"
    end

    test "get decodes the extension fields", %{client: c} do
      stub_json(@received)

      assert {:ok, %ReceivedEmail{} = email} = Receiving.get(c, "r1", html_format: "cid")
      assert req_method() == :get and req_path() == "/emails/receiving/r1"
      assert req_query() == "html_format=cid"
      assert email.html_format == "cid"
      assert email.authentication["spf"] == "pass"
      assert email.raw["download_url"] == "https://api.x.dev/raw/r1"
      assert email.inbox_id == "i1"
      assert [%{"verdict" => "clean"}] = email.inboxes
      assert email.screening["injection_score"] == 3
      assert email.spam_score == 4
      assert email.extracted["code"] == "482913"
      assert email.extracted_text == "Your code is 482913"
      assert email.read == false

      assert {:ok, _} = Receiving.get(c, "r1")
      assert req_query() == nil
    end

    test "reply answers sent or the held draft", %{client: c} do
      stub_json(%{"object" => "email", "id" => "e9", "thread_id" => "t1", "inbox_id" => "i1"})

      params = %{
        text: "Thanks",
        html: "<p>Thanks</p>",
        subject: "Re: Hi",
        cc: "cc@x.dev",
        bcc: ["bcc@x.dev"],
        reply_all: true,
        requires_approval: false,
        from: "bot@x.dev",
        inbox_id: "i1"
      }

      assert {:ok, {:sent, %ThreadEmail{id: "e9", thread_id: "t1", inbox_id: "i1"}}} =
               Receiving.reply(c, "r1", params, idempotency_key: "reply-1")

      assert req_method() == :post and req_path() == "/emails/receiving/r1/reply"
      assert req_headers()["idempotency-key"] == "reply-1"

      assert req_body() == %{
               "text" => "Thanks",
               "html" => "<p>Thanks</p>",
               "subject" => "Re: Hi",
               "cc" => "cc@x.dev",
               "bcc" => ["bcc@x.dev"],
               "reply_all" => true,
               "requires_approval" => false,
               "from" => "bot@x.dev",
               "inbox_id" => "i1"
             }

      stub_response(202, @draft)

      assert {:ok, {:draft, %Draft{status: "pending_approval", approval_reasons: reasons}}} =
               Receiving.reply(c, "r1", %{text: "Thanks"})

      assert reasons == ["send_policy", "ramp"]
      refute Map.has_key?(req_headers(), "idempotency-key")
    end

    test "forward and remove", %{client: c} do
      stub_json(%{"object" => "email", "id" => "e9", "thread_id" => nil, "inbox_id" => nil})

      assert {:ok, {:sent, %ThreadEmail{thread_id: nil}}} =
               Receiving.forward(
                 c,
                 "r1",
                 %{to: ["ops@x.dev"], text: "FYI", mode: "attachment", inbox_id: "i1"},
                 idempotency_key: "fwd-1"
               )

      assert req_method() == :post and req_path() == "/emails/receiving/r1/forward"
      assert req_headers()["idempotency-key"] == "fwd-1"

      assert req_body() == %{
               "to" => ["ops@x.dev"],
               "text" => "FYI",
               "mode" => "attachment",
               "inbox_id" => "i1"
             }

      stub_json(%{"object" => "email", "id" => "r1", "deleted" => true})
      assert {:ok, %ReceivedEmail{deleted: true}} = Receiving.remove(c, "r1")
      assert req_method() == :delete and req_path() == "/emails/receiving/r1"
    end

    test "attachments list and get", %{client: c} do
      stub_json(%{
        "object" => "list",
        "has_more" => false,
        "data" => [%{"id" => "a1", "download_url" => "https://api.x.dev/dl/a1", "size" => 42}]
      })

      assert {:ok,
              %MillionSend.List{data: [%Attachment{download_url: "https://api.x.dev/dl/a1"}]}} =
               Receiving.Attachments.list(c, "r1")

      assert req_method() == :get and req_path() == "/emails/receiving/r1/attachments"
      assert req_query() == nil

      assert {:ok, _} = Receiving.Attachments.list(c, "r1", limit: 2)
      assert req_query() == "limit=2"

      stub_json(%{"object" => "attachment", "id" => "a1", "content_id" => "cid-1"})

      assert {:ok, %Attachment{object: "attachment", content_id: "cid-1"}} =
               Receiving.Attachments.get(c, "r1", "a1")

      assert req_path() == "/emails/receiving/r1/attachments/a1"
    end
  end

  @inbox %{
    "object" => "inbox",
    "id" => "i1",
    "name" => "Signup bot",
    "email_address" => "bot-7f3k@acme.agents.dev",
    "domain_id" => "sd1",
    "receiving_address" => nil,
    "from_name" => nil,
    "unread" => 2,
    "drafts" => 1,
    "last_received" => nil,
    "created_at" => "2026-10-12T10:00:00.000Z",
    "kind" => "agent",
    "shared" => true,
    "expires_at" => "2026-10-13T10:00:00.000Z",
    "quarantined" => 3,
    "pending_approval" => 1
  }

  describe "inboxes" do
    test "create/list/get/update/remove", %{client: c} do
      stub_response(201, @inbox)

      assert {:ok, %Inbox{id: "i1", kind: "agent", shared: true, quarantined: 3}} =
               Inboxes.create(c, %{
                 email_address: "bot@x.dev",
                 name: "Signup bot",
                 kind: "agent",
                 expires_in: "24h",
                 safety: %{accept_from: "anyone", send_cap: nil}
               })

      assert req_method() == :post and req_path() == "/inboxes"

      assert req_body() == %{
               "email_address" => "bot@x.dev",
               "name" => "Signup bot",
               "kind" => "agent",
               "expires_in" => "24h",
               "safety" => %{"accept_from" => "anyone", "send_cap" => nil}
             }

      stub_json(%{
        "object" => "list",
        "has_more" => true,
        "data" => [%{"id" => "i1", "kind" => "human", "shared" => false, "expires_at" => nil}]
      })

      assert {:ok, %MillionSend.List{has_more: true, data: [%Inbox{kind: "human", drafts: nil}]}} =
               Inboxes.list(c, limit: 10, before: "i0", kind: "human")

      assert req_method() == :get and req_path() == "/inboxes"
      assert req_query() == "limit=10&before=i0&kind=human"

      stub_json(@inbox)
      assert {:ok, %Inbox{}} = Inboxes.get(c, "Bot+1@x.dev")
      assert URI.parse(last_request().url).path == "/inboxes/Bot%2B1%40x.dev"

      assert {:ok, _} = Inboxes.update(c, "i1", %{name: "Bot", from_name: "", expires_in: nil})
      assert req_method() == :patch and req_path() == "/inboxes/i1"
      assert req_body() == %{"name" => "Bot", "from_name" => "", "expires_in" => nil}

      stub_json(%{"object" => "inbox", "id" => "i1", "deleted" => true})
      assert {:ok, %Inbox{deleted: true}} = Inboxes.remove(c, "i1")
      assert req_method() == :delete and req_path() == "/inboxes/i1"
    end

    test "safety get and update", %{client: c} do
      stub_json(%{
        "object" => "inbox_safety",
        "inbox_id" => "i1",
        "accept_from" => "verified",
        "allowlist" => ["*@y.dev"],
        "send_policy" => "reply_only",
        "send_cap" => nil,
        "private_codes" => true
      })

      assert {:ok, %Inboxes.Safety{accept_from: "verified", send_cap: nil, private_codes: true}} =
               Inboxes.Safety.get(c, "i1")

      assert req_method() == :get and req_path() == "/inboxes/i1/safety"

      assert {:ok, _} =
               Inboxes.Safety.update(c, "i1", %{
                 accept_from: "allowlist",
                 allowlist: ["ada@y.dev", "*@z.dev"],
                 send_cap: nil
               })

      assert req_method() == :patch and req_path() == "/inboxes/i1/safety"

      assert req_body() == %{
               "accept_from" => "allowlist",
               "allowlist" => ["ada@y.dev", "*@z.dev"],
               "send_cap" => nil
             }
    end

    test "codes latest long-polls; quarantine list and release", %{client: c} do
      stub_json(%{
        "object" => "verification_code",
        "status" => "found",
        "kind" => "otp",
        "code" => "482913",
        "url" => nil,
        "link_domain_matches_sender" => true,
        "email_id" => "r1",
        "from" => "ada@y.dev",
        "received_at" => "2026-10-12T10:00:00.000Z",
        "sender_trust" => "external"
      })

      assert {:ok, %Inboxes.VerificationCode{status: "found", code: "482913"}} =
               Inboxes.Codes.latest(c, "i1", from: "y.dev", wait: 10, max_age: 600)

      assert req_method() == :get and req_path() == "/inboxes/i1/codes/latest"
      assert req_query() == "from=y.dev&wait=10&max_age=600"
      assert last_request().receive_timeout == 25_000

      assert {:ok, _} = Inboxes.Codes.latest(c, "i1")
      assert req_query() == nil

      stub_json(%{
        "object" => "list",
        "has_more" => false,
        "data" => [%{"id" => "r2", "quarantine_reason" => "injection", "injection_score" => 97}]
      })

      assert {:ok,
              %MillionSend.List{
                data: [
                  %Inboxes.QuarantinedEmail{quarantine_reason: "injection", injection_score: 97}
                ]
              }} = Inboxes.Quarantine.list(c, "i1", limit: 5)

      assert req_method() == :get and req_path() == "/inboxes/i1/quarantine"
      assert req_query() == "limit=5"

      stub_json(%{
        "object" => "inbox_release",
        "inbox_id" => "i1",
        "email_id" => "r2",
        "released_at" => "2026-10-12T10:05:00.000Z",
        "trusted_sender" => "eve@z.dev"
      })

      assert {:ok, %Inboxes.Release{trusted_sender: "eve@z.dev"}} =
               Inboxes.Quarantine.release(c, "i1", "r2", trust_sender: true)

      assert req_method() == :post and req_path() == "/inboxes/i1/quarantine/r2/release"
      assert req_body() == %{"trust_sender" => true}

      assert {:ok, _} = Inboxes.Quarantine.release(c, "i1", "r2")
      assert req_body() == %{}
    end

    test "labels list/create/update/remove", %{client: c} do
      stub_json(%{
        "object" => "list",
        "data" => [%{"id" => "l1", "name" => "Billing", "color" => "#FF0000"}]
      })

      assert {:ok, %MillionSend.List{has_more: false, data: [%Label{color: "#FF0000"}]}} =
               Inboxes.Labels.list(c, "i1")

      assert req_method() == :get and req_path() == "/inboxes/i1/labels"

      stub_response(201, %{"object" => "inbox_label", "id" => "l1", "name" => "Billing"})

      assert {:ok, %Label{object: "inbox_label"}} =
               Inboxes.Labels.create(c, "i1", %{name: "Billing", color: "#ff0000"})

      assert req_method() == :post and req_path() == "/inboxes/i1/labels"
      assert req_body() == %{"name" => "Billing", "color" => "#ff0000"}

      assert {:ok, _} = Inboxes.Labels.update(c, "i1", "l1", %{color: "#00FF00"})
      assert req_method() == :patch and req_path() == "/inboxes/i1/labels/l1"
      assert req_body() == %{"color" => "#00FF00"}

      stub_json(%{"object" => "inbox_label", "id" => "l1", "deleted" => true})
      assert {:ok, %Label{deleted: true}} = Inboxes.Labels.remove(c, "i1", "l1")
      assert req_method() == :delete and req_path() == "/inboxes/i1/labels/l1"
    end

    test "threads list/search/get/update/remove", %{client: c} do
      item = %{
        "id" => "t1",
        "subject" => nil,
        "from" => "Ada <ada@y.dev>",
        "labels" => [%{"id" => "l1", "name" => "Billing", "color" => "#FF0000"}],
        "message_count" => 2,
        "has_draft" => true,
        "folder" => "a_folder_from_a_newer_server"
      }

      stub_json(%{"object" => "list", "has_more" => false, "data" => [item]})

      assert {:ok, %MillionSend.List{data: [%Thread{} = thread]}} =
               Inboxes.Threads.list(c, "i1",
                 folders: ["inbox", "archive"],
                 labels: ["l1", "l2"],
                 read: false,
                 limit: 10,
                 after: "t0",
                 include_quarantined: true
               )

      assert req_method() == :get and req_path() == "/inboxes/i1/threads"

      assert req_query() ==
               "limit=10&after=t0&folders=inbox%2Carchive&labels=l1%2Cl2&read=false" <>
                 "&include_quarantined=true"

      assert thread.folder == "a_folder_from_a_newer_server"
      assert [%Label{name: "Billing"}] = thread.labels
      assert thread.message_count == 2

      assert {:ok, _} = Inboxes.Threads.list(c, "i1", folders: [])
      assert req_query() == nil

      stub_json(%{
        "object" => "list",
        "has_more" => false,
        "data" => [
          Map.merge(item, %{
            "matched_email_id" => "r1",
            "highlights" => %{"subject" => ["Your **code**"]}
          })
        ]
      })

      assert {:ok, %MillionSend.List{data: [%Thread{matched_email_id: "r1", highlights: hl}]}} =
               Inboxes.Threads.search(c, "i1",
                 query: "code -spam",
                 from: ["ada", "y.dev"],
                 to: ["bot"],
                 has_attachment: false,
                 start_date: "2026-10-01",
                 end_date: "2026-10-12",
                 folders: ["sent"],
                 limit: 5
               )

      assert hl == %{"subject" => ["Your **code**"]}
      assert req_path() == "/inboxes/i1/threads/search"

      assert req_query() ==
               "limit=5&folders=sent&query=code+-spam&from=ada%2Cy.dev&to=bot" <>
                 "&has_attachment=false&start_date=2026-10-01&end_date=2026-10-12"

      stub_json(%{
        "object" => "inbox_thread",
        "id" => "t1",
        "subject" => "Hi",
        "folder" => "inbox",
        "labels" => [],
        "read" => true,
        "quarantined" => 0
      })

      assert {:ok, %Thread{object: "inbox_thread", quarantined: 0, labels: []}} =
               Inboxes.Threads.get(c, "i1", "t1")

      assert req_method() == :get and req_path() == "/inboxes/i1/threads/t1"

      assert {:ok, _} =
               Inboxes.Threads.update(c, "i1", "t1", %{
                 read: true,
                 folder: "archive",
                 label_id: "l1"
               })

      assert req_method() == :patch and req_path() == "/inboxes/i1/threads/t1"
      assert req_body() == %{"read" => true, "folder" => "archive", "label_id" => "l1"}

      stub_json(%{"object" => "inbox_thread", "id" => "t1", "deleted" => false})
      assert {:ok, %Thread{deleted: false}} = Inboxes.Threads.remove(c, "i1", "t1")
      assert req_method() == :delete and req_path() == "/inboxes/i1/threads/t1"
    end

    test "thread emails list/get/reply/forward", %{client: c} do
      stub_json(%{
        "object" => "list",
        "has_more" => false,
        "data" => [
          %{
            "id" => "r1",
            "direction" => "inbound",
            "screening" => %{"verdict" => "suspicious", "sender_trust" => "unauthenticated"},
            "spam_verdict" => "gray",
            "attachments" => []
          }
        ]
      })

      assert {:ok, %MillionSend.List{data: [%ThreadEmail{direction: "inbound"} = inbound]}} =
               Inboxes.ThreadEmails.list(c, "i1", "t1", after: "r0")

      assert req_method() == :get and req_path() == "/inboxes/i1/threads/t1/emails"
      assert req_query() == "after=r0"
      assert inbound.screening["verdict"] == "suspicious"
      assert inbound.attachments == []

      sent = %{
        "id" => "e9",
        "email_id" => "e9",
        "direction" => "outbound",
        "attachments" => [%{"id" => "0", "filename" => "a.pdf", "size" => 42}],
        "status" => "queued",
        "thread_id" => "t1",
        "inbox_id" => "i1"
      }

      stub_json(sent)

      assert {:ok, %ThreadEmail{status: "queued", attachments: [%Attachment{id: "0"}]}} =
               Inboxes.ThreadEmails.get(c, "i1", "t1", "e9")

      assert req_path() == "/inboxes/i1/threads/t1/emails/e9"

      assert {:ok, {:sent, %ThreadEmail{email_id: "e9", inbox_id: "i1"}}} =
               Inboxes.ThreadEmails.reply(
                 c,
                 "i1",
                 "t1",
                 "r1",
                 %{text: "Thanks", reply_all: true, requires_approval: true},
                 idempotency_key: "k-1"
               )

      assert req_method() == :post and req_path() == "/inboxes/i1/threads/t1/emails/r1/reply"
      assert req_headers()["idempotency-key"] == "k-1"
      assert req_body() == %{"text" => "Thanks", "reply_all" => true, "requires_approval" => true}

      stub_response(202, @draft)

      assert {:ok, {:draft, %Draft{id: "d1"}}} =
               Inboxes.ThreadEmails.forward(c, "i1", "t1", "r1", %{to: ["ops@x.dev"]})

      assert req_path() == "/inboxes/i1/threads/t1/emails/r1/forward"
      assert req_body() == %{"to" => ["ops@x.dev"]}
    end

    test "drafts list/create/get/update/remove/send/reject", %{client: c} do
      stub_json(%{
        "object" => "list",
        "has_more" => false,
        "data" => [%{"id" => "d1", "type" => "standalone", "to" => nil, "snippet" => "Hello"}]
      })

      assert {:ok, %MillionSend.List{data: [%Draft{snippet: "Hello", to: nil}]}} =
               Inboxes.Drafts.list(c, "i1", limit: 3)

      assert req_method() == :get and req_path() == "/inboxes/i1/drafts"
      assert req_query() == "limit=3"

      stub_response(201, @draft)

      assert {:ok, %Draft{type: "reply", expires_at: "2026-10-19T10:00:00.000Z"}} =
               Inboxes.Drafts.create(c, "i1", %{
                 to: "ada@y.dev",
                 text: "Thanks",
                 thread_id: "t1",
                 reply_to_email_id: "r1"
               })

      assert req_method() == :post and req_path() == "/inboxes/i1/drafts"

      assert req_body() == %{
               "to" => "ada@y.dev",
               "text" => "Thanks",
               "thread_id" => "t1",
               "reply_to_email_id" => "r1"
             }

      stub_json(@draft)
      assert {:ok, %Draft{}} = Inboxes.Drafts.get(c, "i1", "d1")
      assert req_method() == :get and req_path() == "/inboxes/i1/drafts/d1"

      assert {:ok, _} =
               Inboxes.Drafts.update(c, "i1", "d1", %{to: nil, subject: nil, text: "New"})

      assert req_method() == :patch and req_path() == "/inboxes/i1/drafts/d1"
      assert req_body() == %{"to" => nil, "subject" => nil, "text" => "New"}

      stub_json(%{
        "object" => "inbox_draft",
        "id" => "d1",
        "thread_id" => "t1",
        "email_id" => "e9"
      })

      assert {:ok, {:sent, %Draft{email_id: "e9", thread_id: "t1"}}} =
               Inboxes.Drafts.send(c, "i1", "d1", idempotency_key: "send-1")

      assert req_method() == :post and req_path() == "/inboxes/i1/drafts/d1/send"
      assert req_body() == nil
      assert req_headers()["idempotency-key"] == "send-1"
      refute Map.has_key?(req_headers(), "content-type")

      stub_response(202, @draft)

      assert {:ok, {:draft, %Draft{status: "pending_approval"}}} =
               Inboxes.Drafts.send(c, "i1", "d1")

      stub_json(Map.put(@draft, "status", "rejected"))
      assert {:ok, %Draft{status: "rejected"}} = Inboxes.Drafts.reject(c, "i1", "d1")
      assert req_method() == :post and req_path() == "/inboxes/i1/drafts/d1/reject"

      stub_json(%{"object" => "inbox_draft", "id" => "d1", "deleted" => true})
      assert {:ok, %Draft{deleted: true}} = Inboxes.Drafts.remove(c, "i1", "d1")
      assert req_method() == :delete and req_path() == "/inboxes/i1/drafts/d1"
    end

    test "a pending draft sent by an agent surfaces approval_required", %{client: c} do
      stub_response(403, %{
        "statusCode" => 403,
        "name" => "approval_required",
        "message" => "A person must approve this draft"
      })

      assert {:error, %MillionSend.Error{name: "approval_required", status_code: 403}} =
               Inboxes.Drafts.send(c, "i1", "d1")
    end
  end

  describe "inbox fields on domains, keys and webhooks" do
    test "receiving_catch_all, inbox_id and inbox_ids reach the wire and decode", %{client: c} do
      stub_json(%{"object" => "domain", "id" => "d1", "receiving_catch_all" => true})

      assert {:ok, %MillionSend.Domains.Domain{receiving_catch_all: true}} =
               MillionSend.Domains.update(c, "d1", %{receiving_catch_all: false})

      assert req_body() == %{"receiving_catch_all" => false}

      stub_json(%{"id" => "k1", "token" => "ms_secret", "inbox_id" => "i1"})

      assert {:ok, %MillionSend.ApiKeys.ApiKey{inbox_id: "i1"}} =
               MillionSend.ApiKeys.create(c, %{name: "agent", inbox_id: "i1"})

      assert req_body() == %{"name" => "agent", "inbox_id" => "i1"}

      stub_json(%{
        "object" => "webhook",
        "id" => "w1",
        "events" => ["inbox.thread.created"],
        "inbox_ids" => ["i1", "i2"]
      })

      assert {:ok, %MillionSend.Webhooks.Webhook{inbox_ids: ["i1", "i2"]}} =
               MillionSend.Webhooks.update(c, "w1", %{inbox_ids: nil})

      assert req_body() == %{"inbox_ids" => nil}
    end
  end
end
