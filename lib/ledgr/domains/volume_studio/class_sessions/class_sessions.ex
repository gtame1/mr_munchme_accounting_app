defmodule Ledgr.Domains.VolumeStudio.ClassSessions do
  @moduledoc """
  Context module for managing Volume Studio class sessions and bookings.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.VolumeStudio.ClassSessions.{ClassSession, ClassBooking}
  alias Ledgr.Domains.VolumeStudio.Subscriptions.Subscription
  alias Ledgr.Domains.VolumeStudio.Accounting.VolumeStudioAccounting

  # ── Class Sessions ────────────────────────────────────────────────────

  @doc """
  Returns a list of class sessions.

  Options:
    - `:status` — filter by status string, e.g. "scheduled"
    - `:from` — filter sessions scheduled after this datetime
    - `:to` — filter sessions scheduled before this datetime
  """
  def list_class_sessions(opts \\ []) do
    status = Keyword.get(opts, :status)
    from_dt = Keyword.get(opts, :from)
    to_dt = Keyword.get(opts, :to)

    ClassSession
    |> where([s], is_nil(s.deleted_at))
    |> maybe_filter_status(status)
    |> maybe_filter_from(from_dt)
    |> maybe_filter_to(to_dt)
    |> order_by(desc: :scheduled_at)
    |> preload(:instructor)
    |> Repo.all()
  end

  @doc "Gets a single class session with instructor and bookings preloaded. Raises if not found."
  def get_class_session!(id) do
    from(s in ClassSession, where: s.id == ^id and is_nil(s.deleted_at))
    |> preload([:instructor, class_bookings: [:customer, subscription: :subscription_plan]])
    |> Repo.one!()
  end

  @doc "Returns a changeset for the given session and attrs."
  def change_class_session(%ClassSession{} = session, attrs \\ %{}) do
    ClassSession.changeset(session, attrs)
  end

  @doc "Creates a class session."
  def create_class_session(attrs \\ %{}) do
    %ClassSession{}
    |> ClassSession.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a class session."
  def update_class_session(%ClassSession{} = session, attrs) do
    session
    |> ClassSession.changeset(attrs)
    |> Repo.update()
  end

  @doc "Soft-deletes a class session and all its bookings."
  def delete_class_session(%ClassSession{} = session) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      from(b in ClassBooking, where: b.class_session_id == ^session.id and is_nil(b.deleted_at))
      |> Repo.update_all(set: [deleted_at: now, updated_at: now])

      session
      |> Ecto.Changeset.change(deleted_at: now)
      |> Repo.update!()
    end)
  end

  # ── Bookings ──────────────────────────────────────────────────────────

  @doc "Returns all bookings for the given session_id with customer preloaded."
  def list_bookings_for_session(session_id) do
    ClassBooking
    |> where(class_session_id: ^session_id)
    |> where([b], is_nil(b.deleted_at))
    |> preload([:customer, :subscription])
    |> Repo.all()
  end

  @doc "Returns a changeset for the given booking and attrs."
  def change_booking(%ClassBooking{} = booking, attrs \\ %{}) do
    ClassBooking.changeset(booking, attrs)
  end

  @doc "Creates a booking. Enforces unique constraint (customer + session)."
  def create_booking(attrs \\ %{}) do
    %ClassBooking{}
    |> ClassBooking.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Checks in a booking.

  In a transaction:
    1. Updates booking.status → "checked_in"
    2. If booking.subscription_id present → increments subscription.classes_used
       - Extra plans: recognizes all deferred revenue immediately
       - Package plans (class_limit > 0): recognizes deferred ÷ classes remaining
  """
  def checkin(%ClassBooking{} = booking) do
    Repo.transaction(fn ->
      updated =
        booking
        |> ClassBooking.changeset(%{status: "checked_in"})
        |> Repo.update!()

      if updated.subscription_id do
        sub  = Repo.get!(Subscription, updated.subscription_id) |> Repo.preload(:subscription_plan)
        plan = sub.subscription_plan

        if plan.class_limit && sub.classes_used >= plan.class_limit do
          Repo.rollback(:class_limit_reached)
        else
          classes_before = sub.classes_used

          updated_sub =
            sub
            |> Ecto.Changeset.change(classes_used: classes_before + 1)
            |> Repo.update!()

          recognize_on_checkin(updated_sub, updated, plan, classes_before)
        end
      end

      updated
    end)
  end

  @doc """
  Marks a booking as attended (checked_in) or no_show.

  Handles subscription classes_used counter in both directions:
    - Not checked_in → checked_in: increments classes_used (enforcing plan limit)
    - Was checked_in → no_show:    decrements classes_used
  """
  def mark_attendance(%ClassBooking{} = booking, attended) when is_boolean(attended) do
    new_status = if attended, do: "checked_in", else: "no_show"

    Repo.transaction(fn ->
      updated =
        booking
        |> ClassBooking.changeset(%{status: new_status})
        |> Repo.update!()

      cond do
        # Transitioning TO checked_in from something other than checked_in
        attended && booking.status != "checked_in" && booking.subscription_id ->
          sub =
            Repo.get!(Subscription, booking.subscription_id)
            |> Repo.preload(:subscription_plan)

          plan = sub.subscription_plan

          if plan.class_limit && sub.classes_used >= plan.class_limit do
            Repo.rollback(:class_limit_reached)
          else
            classes_before = sub.classes_used

            updated_sub =
              sub
              |> Ecto.Changeset.change(classes_used: classes_before + 1)
              |> Repo.update!()

            recognize_on_checkin(updated_sub, updated, plan, classes_before)
          end

        # Transitioning FROM checked_in to no_show
        !attended && booking.status == "checked_in" && booking.subscription_id ->
          sub = Repo.get!(Subscription, booking.subscription_id)

          sub
          |> Ecto.Changeset.change(classes_used: max(sub.classes_used - 1, 0))
          |> Repo.update!()

        true ->
          :ok
      end

      updated
    end)
  end

  @doc """
  Cancels a booking by updating its status.

  If the booking was already checked in, decrements `classes_used` on the linked
  subscription so the counter stays accurate.
  """
  def cancel_booking(%ClassBooking{} = booking) do
    Repo.transaction(fn ->
      updated =
        booking
        |> ClassBooking.changeset(%{status: "cancelled"})
        |> Repo.update!()

      if booking.status == "checked_in" && booking.subscription_id do
        sub = Repo.get!(Subscription, booking.subscription_id)

        sub
        |> Ecto.Changeset.change(classes_used: max(sub.classes_used - 1, 0))
        |> Repo.update!()
      end

      updated
    end)
  end

  @doc """
  Returns a booking summary map for a session.

  Keys: :total, :booked, :checked_in, :no_show, :cancelled, :available
  """
  def booking_summary(%ClassSession{} = session) do
    bookings =
      ClassBooking
      |> where(class_session_id: ^session.id)
      |> where([b], is_nil(b.deleted_at))
      |> Repo.all()

    counts = Enum.frequencies_by(bookings, & &1.status)

    booked = Map.get(counts, "booked", 0)
    checked_in = Map.get(counts, "checked_in", 0)
    no_show = Map.get(counts, "no_show", 0)
    cancelled = Map.get(counts, "cancelled", 0)
    total = booked + checked_in + no_show + cancelled

    available =
      if session.capacity do
        max(session.capacity - booked - checked_in, 0)
      else
        nil
      end

    %{
      total: total,
      booked: booked,
      checked_in: checked_in,
      no_show: no_show,
      cancelled: cancelled,
      available: available
    }
  end

  @doc """
  Returns a map of %Date{} => [ClassSession] for all sessions in the given year/month.
  Sessions are ordered by scheduled_at ascending within each date bucket.
  """
  def list_class_sessions_for_calendar_month(year, month) do
    first_day = Date.new!(year, month, 1)
    last_day  = Date.end_of_month(first_day)
    from_dt   = first_day |> NaiveDateTime.new!(~T[00:00:00]) |> DateTime.from_naive!("Etc/UTC")
    to_dt     = last_day |> Date.add(1) |> NaiveDateTime.new!(~T[00:00:00]) |> DateTime.from_naive!("Etc/UTC")

    ClassSession
    |> where([s], s.scheduled_at >= ^from_dt and s.scheduled_at < ^to_dt)
    |> where([s], is_nil(s.deleted_at))
    |> order_by(asc: :scheduled_at)
    |> preload(:instructor)
    |> Repo.all()
    |> Enum.group_by(fn s -> DateTime.to_date(s.scheduled_at) end)
  end

  # ── Private helpers ──────────────────────────────────────────────────

  # Handles revenue recognition at check-in time based on plan type:
  #
  #   extra plans   → recognize all remaining deferred revenue at once
  #   package plans → recognize deferred ÷ classes remaining before this check-in
  #   other plans   → time-based only; no recognition on check-in
  #
  # `sub` is the subscription AFTER classes_used was incremented.
  # `classes_before` is the classes_used value BEFORE the increment.
  defp recognize_on_checkin(sub, booking, plan, classes_before) do
    cond do
      plan.plan_type == "extra" && sub.deferred_revenue_cents > 0 ->
        to_recognize = sub.deferred_revenue_cents

        sub
        |> Ecto.Changeset.change(
          deferred_revenue_cents:   0,
          recognized_revenue_cents: sub.recognized_revenue_cents + to_recognize
        )
        |> Repo.update!()

        VolumeStudioAccounting.recognize_subscription_revenue(sub, to_recognize)

      plan.class_limit && plan.class_limit > 0 &&
          plan.plan_type != "extra" && sub.deferred_revenue_cents > 0 ->
        classes_remaining = max(plan.class_limit - classes_before, 1)
        to_recognize = round(sub.deferred_revenue_cents / classes_remaining)

        if to_recognize > 0 do
          sub
          |> Ecto.Changeset.change(
            deferred_revenue_cents:   sub.deferred_revenue_cents - to_recognize,
            recognized_revenue_cents: sub.recognized_revenue_cents + to_recognize
          )
          |> Repo.update!()

          VolumeStudioAccounting.recognize_subscription_revenue_for_booking(sub, booking, to_recognize)
        end

      true ->
        :ok
    end
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  defp maybe_filter_from(query, nil), do: query
  defp maybe_filter_from(query, dt), do: where(query, [s], s.scheduled_at >= ^dt)

  defp maybe_filter_to(query, nil), do: query
  defp maybe_filter_to(query, dt), do: where(query, [s], s.scheduled_at <= ^dt)
end
