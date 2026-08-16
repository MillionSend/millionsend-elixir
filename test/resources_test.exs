defmodule MillionSend.ResourcesTest do
  use ExUnit.Case, async: true

  import MillionSend.Test.Helpers

  setup do
    {:ok, client: client()}
  end

  describe "emails" do
    test "get and cancel hit the right paths", %{client: c} do
      assert {:ok, _} = MillionSend.Emails.get(c, "e1")
      assert req_method() == :get
      assert req_path() == "/emails/e1"

      assert {:ok, _} = MillionSend.Emails.cancel(c, "e1")
      assert req_method() == :post
      assert req_path() == "/emails/e1/cancel"
    end
  end

  describe "batch" do
    test "sends a bare array body with an idempotency key", %{client: c} do
      stub_json(%{"data" => [%{"id" => "1"}, %{"id" => "2"}]})

      assert {:ok, [a, b]} =
               MillionSend.Emails.send_batch(
                 c,
                 [
                   %{from: "a@x.dev", to: "b@x.dev", subject: "1", text: "one"},
                   %{from: "a@x.dev", to: "c@x.dev", subject: "2", text: "two"}
                 ],
                 idempotency_key: "batch-1"
               )

      assert req_path() == "/emails/batch"
      assert is_list(req_body())
      assert length(req_body()) == 2
      assert req_headers()["idempotency-key"] == "batch-1"
      assert a.id == "1" and b.id == "2"
    end
  end

  describe "audiences" do
    test "covers create/get/list/remove", %{client: c} do
      assert {:ok, _} = MillionSend.Audiences.create(c, %{name: "Users"})
      assert req_method() == :post and req_path() == "/audiences"
      assert req_body() == %{"name" => "Users"}

      assert {:ok, _} = MillionSend.Audiences.get(c, "a1")
      assert req_path() == "/audiences/a1"

      assert {:ok, %MillionSend.List{}} = MillionSend.Audiences.list(c, limit: 10)
      assert req_path() == "/audiences"
      assert req_query() == "limit=10"

      assert {:ok, _} = MillionSend.Audiences.remove(c, "a1")
      assert req_method() == :delete and req_path() == "/audiences/a1"
    end
  end

  describe "contacts" do
    test "creates audience-scoped and top-level", %{client: c} do
      assert {:ok, _} =
               MillionSend.Contacts.create(c, %{
                 audience_id: "a1",
                 email: "c@x.dev",
                 first_name: "Ada"
               })

      assert req_path() == "/audiences/a1/contacts"
      assert req_body() == %{"email" => "c@x.dev", "first_name" => "Ada"}

      assert {:ok, _} = MillionSend.Contacts.create(c, %{email: "c@x.dev"})
      assert req_path() == "/contacts"
    end

    test "addresses by string id, email, and scoped id", %{client: c} do
      assert {:ok, _} = MillionSend.Contacts.get(c, "c1")
      assert req_path() == "/contacts/c1"

      assert {:ok, _} = MillionSend.Contacts.get(c, %{email: "c@x.dev"})
      assert req_path() == "/contacts/c%40x.dev"

      assert {:ok, _} = MillionSend.Contacts.get(c, %{audience_id: "a1", id: "c1"})
      assert req_path() == "/audiences/a1/contacts/c1"
    end

    test "email wins over id when both are given", %{client: c} do
      assert {:ok, _} = MillionSend.Contacts.get(c, %{id: "c1", email: "c@x.dev"})
      assert req_path() == "/contacts/c%40x.dev"
    end

    test "update sends only provided keys (nil clears)", %{client: c} do
      assert {:ok, _} =
               MillionSend.Contacts.update(c, %{id: "c1", first_name: nil, unsubscribed: true})

      assert req_method() == :patch and req_path() == "/contacts/c1"
      assert req_body() == %{"first_name" => nil, "unsubscribed" => true}
    end

    test "remove and scoped list", %{client: c} do
      assert {:ok, _} = MillionSend.Contacts.remove(c, %{email: "c@x.dev"})
      assert req_method() == :delete

      assert {:ok, %MillionSend.List{}} =
               MillionSend.Contacts.list(c, audience_id: "a1", after: "cur")

      assert req_path() == "/audiences/a1/contacts"
      assert req_query() == "after=cur"
    end

    test "update_topics patches /contacts/:id/topics with the bare array", %{client: c} do
      stub_json(%{"id" => "c1"})

      assert {:ok, _} =
               MillionSend.Contacts.update_topics(c, %{
                 id: "c1",
                 topics: [%{id: "t1", subscription: "opt_out"}]
               })

      assert req_method() == :patch and req_path() == "/contacts/c1/topics"
      assert req_body() == [%{"id" => "t1", "subscription" => "opt_out"}]
    end
  end

  describe "broadcasts" do
    test "covers the full lifecycle", %{client: c} do
      assert {:ok, _} =
               MillionSend.Broadcasts.create(c, %{
                 audience_id: "a1",
                 from: "a@x.dev",
                 subject: "News",
                 html: "<p>hi</p>"
               })

      assert req_path() == "/broadcasts"

      assert req_body() == %{
               "audience_id" => "a1",
               "from" => "a@x.dev",
               "subject" => "News",
               "html" => "<p>hi</p>"
             }

      assert {:ok, _} = MillionSend.Broadcasts.get(c, "b1")
      assert req_path() == "/broadcasts/b1"

      assert {:ok, %MillionSend.List{}} = MillionSend.Broadcasts.list(c)
      assert req_path() == "/broadcasts"

      assert {:ok, _} = MillionSend.Broadcasts.update(c, "b1", %{subject: "New"})
      assert req_method() == :patch and req_path() == "/broadcasts/b1"

      assert {:ok, _} = MillionSend.Broadcasts.send(c, "b1", scheduled_at: "2999-01-01T00:00:00Z")
      assert req_path() == "/broadcasts/b1/send"
      assert req_body() == %{"scheduled_at" => "2999-01-01T00:00:00Z"}

      assert {:ok, _} = MillionSend.Broadcasts.cancel(c, "b1")
      assert req_path() == "/broadcasts/b1/cancel"

      assert {:ok, _} = MillionSend.Broadcasts.remove(c, "b1")
      assert req_method() == :delete
    end

    test "send now posts an empty body", %{client: c} do
      assert {:ok, _} = MillionSend.Broadcasts.send(c, "b1")
      assert req_path() == "/broadcasts/b1/send"
      assert req_body() == %{}
    end
  end

  describe "topics" do
    test "covers create/get/list/remove", %{client: c} do
      assert {:ok, _} =
               MillionSend.Topics.create(c, %{name: "Product", default_subscription: "opt_in"})

      assert req_body() == %{"name" => "Product", "default_subscription" => "opt_in"}

      assert {:ok, _} = MillionSend.Topics.get(c, "t1")
      assert req_path() == "/topics/t1"

      stub_json(%{"data" => [%{"id" => "t1", "name" => "Product"}]})
      assert {:ok, [topic]} = MillionSend.Topics.list(c)
      assert req_path() == "/topics"
      assert topic.__struct__ == MillionSend.Topics.Topic
      assert topic.id == "t1"

      assert {:ok, _} = MillionSend.Topics.remove(c, "t1")
      assert req_method() == :delete
    end
  end

  describe "segments" do
    test "covers create/get/list/update/remove on /segments2", %{client: c} do
      filter = %{match: "all", conditions: [%{field: "email", op: "is_set"}]}

      assert {:ok, _} =
               MillionSend.Segments.create(c, %{name: "Active", audience_id: "a1", filter: filter})

      assert req_path() == "/segments2"

      assert req_body() == %{
               "name" => "Active",
               "audience_id" => "a1",
               "filter" => %{
                 "match" => "all",
                 "conditions" => [%{"field" => "email", "op" => "is_set"}]
               }
             }

      assert {:ok, _} = MillionSend.Segments.get(c, "s1")
      assert req_path() == "/segments2/s1"

      assert {:ok, %MillionSend.List{}} = MillionSend.Segments.list(c, before: "cur")
      assert req_path() == "/segments2"
      assert req_query() == "before=cur"

      assert {:ok, _} = MillionSend.Segments.update(c, "s1", %{name: "Renamed"})
      assert req_method() == :patch and req_path() == "/segments2/s1"

      assert {:ok, _} = MillionSend.Segments.remove(c, "s1")
      assert req_method() == :delete
    end
  end

  describe "casting" do
    test "list envelope casts items and carries has_more", %{client: c} do
      stub_json(%{
        "object" => "list",
        "has_more" => true,
        "data" => [%{"id" => "a1", "name" => "Users", "created_at" => "2026-01-01"}]
      })

      assert {:ok, list} = MillionSend.Audiences.list(c)
      assert list.has_more == true
      assert [%MillionSend.Audiences.Audience{id: "a1", name: "Users"}] = list.data
    end

    test "delete response casts deleted flag", %{client: c} do
      stub_json(%{"object" => "audience", "id" => "a1", "deleted" => true})

      assert {:ok, %MillionSend.Audiences.Audience{deleted: true, id: "a1"}} =
               MillionSend.Audiences.remove(c, "a1")
    end
  end
end
