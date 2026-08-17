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

  describe "contacts" do
    test "creates at the top-level collection", %{client: c} do
      assert {:ok, _} =
               MillionSend.Contacts.create(c, %{email: "c@x.dev", first_name: "Ada"})

      assert req_method() == :post and req_path() == "/contacts"
      assert req_body() == %{"email" => "c@x.dev", "first_name" => "Ada"}
    end

    test "addresses by string id and by email", %{client: c} do
      assert {:ok, _} = MillionSend.Contacts.get(c, "c1")
      assert req_path() == "/contacts/c1"

      assert {:ok, _} = MillionSend.Contacts.get(c, %{email: "c@x.dev"})
      assert req_path() == "/contacts/c%40x.dev"
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

    test "remove and list", %{client: c} do
      assert {:ok, _} = MillionSend.Contacts.remove(c, %{email: "c@x.dev"})
      assert req_method() == :delete

      assert {:ok, %MillionSend.List{}} = MillionSend.Contacts.list(c, after: "cur")
      assert req_path() == "/contacts"
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
                 segment_id: "s1",
                 from: "a@x.dev",
                 subject: "News",
                 html: "<p>hi</p>"
               })

      assert req_path() == "/broadcasts"

      assert req_body() == %{
               "segment_id" => "s1",
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
    test "covers create/get/list/update/remove on /segments", %{client: c} do
      filter = %{match: "all", conditions: [%{field: "email", op: "is_set"}]}

      assert {:ok, _} = MillionSend.Segments.create(c, %{name: "Active", filter: filter})

      assert req_path() == "/segments"

      assert req_body() == %{
               "name" => "Active",
               "filter" => %{
                 "match" => "all",
                 "conditions" => [%{"field" => "email", "op" => "is_set"}]
               }
             }

      assert {:ok, _} = MillionSend.Segments.get(c, "s1")
      assert req_path() == "/segments/s1"

      assert {:ok, %MillionSend.List{}} = MillionSend.Segments.list(c, before: "cur")
      assert req_path() == "/segments"
      assert req_query() == "before=cur"

      assert {:ok, _} = MillionSend.Segments.update(c, "s1", %{name: "Renamed"})
      assert req_method() == :patch and req_path() == "/segments/s1"

      assert {:ok, _} = MillionSend.Segments.remove(c, "s1")
      assert req_method() == :delete
    end
  end

  describe "casting" do
    test "list envelope casts items and carries has_more", %{client: c} do
      stub_json(%{
        "object" => "list",
        "has_more" => true,
        "data" => [%{"id" => "s1", "name" => "Active", "created_at" => "2026-01-01"}]
      })

      assert {:ok, list} = MillionSend.Segments.list(c)
      assert list.has_more == true
      assert [%MillionSend.Segments.Segment{id: "s1", name: "Active"}] = list.data
    end

    test "delete response casts deleted flag", %{client: c} do
      stub_json(%{"object" => "segment", "id" => "s1", "deleted" => true})

      assert {:ok, %MillionSend.Segments.Segment{deleted: true, id: "s1"}} =
               MillionSend.Segments.remove(c, "s1")
    end
  end
end
