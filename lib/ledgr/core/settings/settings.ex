defmodule Ledgr.Core.Settings do
  @moduledoc """
  Context for application-wide settings stored as key-value pairs.
  """

  import Ecto.Query
  alias Ledgr.Repo
  alias Ledgr.Core.Settings.AppSetting

  @doc """
  Gets the value for a given key. Returns nil if not found.
  """
  def get(key) when is_binary(key) do
    case Repo.one(from s in AppSetting, where: s.key == ^key, select: s.value) do
      nil -> nil
      value -> value
    end
  end

  @doc """
  Sets a key-value pair. Upserts if the key already exists.
  """
  def set(key, value) when is_binary(key) do
    case Repo.one(from s in AppSetting, where: s.key == ^key) do
      nil ->
        %AppSetting{}
        |> AppSetting.changeset(%{key: key, value: value})
        |> Repo.insert()

      existing ->
        existing
        |> AppSetting.changeset(%{value: value})
        |> Repo.update()
    end
  end

  @doc """
  Gets the last reconciled date. Returns a Date or nil.
  """
  def get_last_reconciled_date do
    case get("last_reconciled_date") do
      nil -> nil
      date_string -> Date.from_iso8601!(date_string)
    end
  end

  @doc """
  Sets the last reconciled date.
  """
  def set_last_reconciled_date(%Date{} = date) do
    set("last_reconciled_date", Date.to_iso8601(date))
  end

  @doc """
  Gets the last inventory reconciled date. Returns a Date or nil.
  """
  def get_last_inventory_reconciled_date do
    case get("last_inventory_reconciled_date") do
      nil -> nil
      date_string -> Date.from_iso8601!(date_string)
    end
  end

  @doc """
  Sets the last inventory reconciled date.
  """
  def set_last_inventory_reconciled_date(%Date{} = date) do
    set("last_inventory_reconciled_date", Date.to_iso8601(date))
  end
end
