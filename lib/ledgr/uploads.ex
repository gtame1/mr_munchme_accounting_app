defmodule Ledgr.Uploads do
  @moduledoc """
  Simple file upload helper for saving product images to the local filesystem.

  Files are saved to `priv/static/uploads/products/` with a UUID prefix
  to avoid filename collisions. Returns URL paths relative to the static root.
  """

  @upload_dir "priv/static/uploads/products"

  @doc """
  Saves a `Plug.Upload` to the local filesystem.

  Returns `{:ok, url_path}` where `url_path` is like `/uploads/products/abc123-photo.jpg`.
  """
  def save(%Plug.Upload{path: tmp_path, filename: filename}) do
    # Ensure upload directory exists
    upload_dir = Application.app_dir(:ledgr, @upload_dir)
    File.mkdir_p!(upload_dir)

    # Generate a unique filename
    ext = Path.extname(filename) |> String.downcase()
    safe_name = Ecto.UUID.generate() <> ext
    dest_path = Path.join(upload_dir, safe_name)

    case File.cp(tmp_path, dest_path) do
      :ok ->
        url_path = "/uploads/products/#{safe_name}"
        {:ok, url_path}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def save(_), do: {:error, :invalid_upload}

  @doc """
  Deletes an uploaded file given its URL path (e.g., `/uploads/products/abc123-photo.jpg`).

  Only deletes files within the uploads directory for safety.
  Returns `:ok` or `{:error, reason}`.
  """
  def delete("/uploads/products/" <> filename) do
    upload_dir = Application.app_dir(:ledgr, @upload_dir)
    file_path = Path.join(upload_dir, filename)

    case File.rm(file_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok  # Already deleted, that's fine
      {:error, reason} -> {:error, reason}
    end
  end

  # Don't delete external URLs or paths outside our upload dir
  def delete(_url), do: :ok
end
