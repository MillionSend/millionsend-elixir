defmodule MillionSend.List do
  @moduledoc """
  The pagination envelope returned by list endpoints: `data` holds the cast
  structs, `has_more` says whether another page exists in the direction you
  page. Paginate with the `after:`/`before:` keyset cursors.

  Lists run newest first (MillionSend v0.13.0 and later): `after:` takes the
  last id of a page and pages toward older items, `before:` takes the first id
  and pages toward newer ones. Threads sort by last activity, drafts by last
  update, and a thread's emails run oldest first.
  """

  @type t :: %__MODULE__{object: String.t() | nil, data: list(), has_more: boolean()}

  defstruct object: "list", data: [], has_more: false
end
