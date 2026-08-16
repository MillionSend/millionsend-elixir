# End-to-end smoke test against a real MillionSend instance. Opt-in: only
# compiled and run when MILLIONSEND_API_KEY is set (and, if not localhost:3001,
# MILLIONSEND_BASE_URL). It exercises the audience + contact lifecycle, which
# needs no verified domain. Sending is not asserted here — that requires a
# verified sender domain.
#
#   MILLIONSEND_API_KEY=ms_... MILLIONSEND_BASE_URL=http://localhost:3001 mix test
if System.get_env("MILLIONSEND_API_KEY") do
  defmodule MillionSend.E2ETest do
    use ExUnit.Case, async: false

    setup_all do
      client = MillionSend.client()
      {:ok, client: client}
    end

    test "creates, reads, updates and deletes a contact in an audience", %{client: client} do
      assert {:ok, audience} =
               MillionSend.Audiences.create(client, %{
                 name: "sdk-e2e-#{System.unique_integer([:positive])}"
               })

      assert audience.id

      on_exit(fn -> MillionSend.Audiences.remove(client, audience.id) end)

      email = "sdk-e2e-#{System.unique_integer([:positive])}@example.com"

      assert {:ok, _} =
               MillionSend.Contacts.create(client, %{
                 audience_id: audience.id,
                 email: email,
                 first_name: "Ada"
               })

      assert {:ok, fetched} =
               MillionSend.Contacts.get(client, %{audience_id: audience.id, email: email})

      assert fetched.email == email
      assert fetched.first_name == "Ada"

      assert {:ok, _} =
               MillionSend.Contacts.update(client, %{
                 audience_id: audience.id,
                 email: email,
                 unsubscribed: true
               })

      assert {:ok, removed} =
               MillionSend.Contacts.remove(client, %{audience_id: audience.id, email: email})

      assert removed.deleted == true
    end

    test "surfaces a not_found error without raising", %{client: client} do
      assert {:error, error} =
               MillionSend.Contacts.get(client, %{email: "does-not-exist@example.com"})

      assert error.name == "not_found"
    end
  end
end
