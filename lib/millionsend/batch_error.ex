defmodule MillionSend.BatchError do
  @moduledoc """
  One rejected item of a permissive batch (`batch_validation: :permissive`):
  its position in the request array and the validation message. Contacts batch
  errors also carry the `status_code` and `name` strict mode would answer for
  the item (MillionSend v0.12.0 and later); email batch errors leave them `nil`.
  """

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          message: String.t(),
          status_code: non_neg_integer() | nil,
          name: String.t() | nil
        }

  defstruct [:index, :message, :status_code, :name]

  @doc false
  @spec cast_list([map()] | nil) :: [t()]
  def cast_list(nil), do: []

  def cast_list(list) do
    # The wire key is camelCase `statusCode`, as on `MillionSend.Error`.
    Enum.map(
      list,
      &%{MillionSend.Request.cast_struct(__MODULE__, &1) | status_code: &1["statusCode"]}
    )
  end
end
