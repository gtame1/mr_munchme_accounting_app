defmodule Ledgr.Core.Settings.AppSetting do
  use Ecto.Schema
  import Ecto.Changeset

  schema "app_settings" do
    field :key, :string
    field :value, :string

    timestamps()
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key])
    |> unique_constraint(:key)
  end
end
