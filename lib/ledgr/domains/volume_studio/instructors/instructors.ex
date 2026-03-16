defmodule Ledgr.Domains.VolumeStudio.Instructors do
  @moduledoc """
  Context module for managing Volume Studio instructors.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.VolumeStudio.Instructors.Instructor

  @doc "Returns all instructors, ordered by name."
  def list_instructors do
    Instructor
    |> where([i], is_nil(i.deleted_at))
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc "Returns only active instructors, ordered by name. Useful for select dropdowns."
  def list_active_instructors do
    Instructor
    |> where([i], i.active == true and is_nil(i.deleted_at))
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc "Gets a single instructor. Raises if not found."
  def get_instructor!(id) do
    from(i in Instructor, where: i.id == ^id and is_nil(i.deleted_at))
    |> Repo.one!()
  end

  @doc "Returns a changeset for the given instructor and attrs."
  def change_instructor(%Instructor{} = instructor, attrs \\ %{}) do
    Instructor.changeset(instructor, attrs)
  end

  @doc "Creates an instructor."
  def create_instructor(attrs \\ %{}) do
    %Instructor{}
    |> Instructor.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates an instructor."
  def update_instructor(%Instructor{} = instructor, attrs) do
    instructor
    |> Instructor.changeset(attrs)
    |> Repo.update()
  end

  @doc "Soft-deletes an instructor."
  def delete_instructor(%Instructor{} = instructor) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    instructor
    |> Ecto.Changeset.change(deleted_at: now)
    |> Repo.update()
  end
end
