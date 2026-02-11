defmodule Ledgr.Core.Accounts do
  @moduledoc """
  Account management and authentication.

  All queries go through Ledgr.Repo, which dispatches to the
  currently active per-domain repo.
  """

  alias Ledgr.Core.Accounts.User
  alias Ledgr.Repo

  @doc "Get a user by email."
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Authenticate a user by email and password.
  Returns {:ok, user} or {:error, :invalid_credentials}.
  """
  def authenticate_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)

    cond do
      user && Bcrypt.verify_pass(password, user.password_hash) ->
        {:ok, user}

      user ->
        {:error, :invalid_credentials}

      true ->
        # No user found - run dummy check to prevent timing attacks
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  @doc "Create a new user."
  def create_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Returns a registration changeset for form rendering."
  def change_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs)
  end
end
