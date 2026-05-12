defmodule LedgrWeb.Domains.HelloDoctor.DoctorPayoutController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.DashboardMetrics
  alias Ledgr.Domains.HelloDoctor.DoctorPayoutImport
  alias Ledgr.Domains.HelloDoctor.ExternalCostAccounting
  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.ExternalCosts.ExternalCost
  alias Ledgr.Core.Accounting

  import Ecto.Query, warn: false

  # ── Doctor payout report ────────────────────────────────────────

  def index(conn, params) do
    today = Ledgr.Domains.HelloDoctor.today()
    start_date = parse_date(params["start_date"]) || Date.beginning_of_month(today)
    end_date = parse_date(params["end_date"]) || today

    report = DashboardMetrics.doctor_payout_report(start_date, end_date)

    render(conn, :index,
      report: report,
      start_date: start_date,
      end_date: end_date
    )
  end

  # ── Record a doctor payout (mark as paid) ───────────────────────

  @doc """
  Records that HelloDoctor has paid a doctor.
  Creates a journal entry:
    DEBIT  2000 Doctor Payable   [amount_pesos]
    CREDIT 1010 Bank - MXN       [amount_pesos]
  """
  def record_payout(conn, %{
        "doctor_id" => doctor_id,
        "amount" => amount_str,
        "description" => description
      }) do
    amount_pesos = String.to_float(amount_str)
    amount_cents = round(amount_pesos * 100)

    doctor_payable = Accounting.get_account_by_code!("2000")
    bank_mxn = Accounting.get_account_by_code!("1010")

    entry_attrs = %{
      date: Ledgr.Domains.HelloDoctor.today(),
      entry_type: "doctor_payout",
      reference: "DoctorPayout-#{doctor_id}",
      description: description || "Doctor payout",
      payee: "Doctor ##{doctor_id}"
    }

    lines = [
      %{
        account_id: doctor_payable.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: "Clearing doctor payable — #{description}"
      },
      %{
        account_id: bank_mxn.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: "Bank transfer to doctor — #{description}"
      }
    ]

    case Accounting.create_journal_entry_with_lines(entry_attrs, lines) do
      {:ok, _entry} ->
        conn
        |> put_flash(
          :info,
          "Payout of $#{:erlang.float_to_binary(amount_pesos, decimals: 2)} MXN recorded successfully."
        )
        |> redirect(to: dp(conn, "/doctor-payouts"))

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Failed to record payout: #{inspect(changeset)}")
        |> redirect(to: dp(conn, "/doctor-payouts"))
    end
  end

  # ── Post single external cost to GL ────────────────────────────

  def post_cost(conn, %{"id" => id}) do
    cost = Repo.get!(ExternalCost, id)

    case ExternalCostAccounting.post_to_gl(cost) do
      {:ok, :already_posted, _} ->
        conn
        |> put_flash(:info, "Already posted to GL.")
        |> redirect(to: dp(conn, "/"))

      {:ok, updated} ->
        mxn = Float.round(updated.amount_mxn_cents / 100.0, 2)

        conn
        |> put_flash(
          :info,
          "Posted to GL: $#{:erlang.float_to_binary(mxn, decimals: 2)} MXN (JE ##{updated.journal_entry_id})."
        )
        |> redirect(to: dp(conn, "/"))

      {:error, :zero_amount} ->
        conn
        |> put_flash(:error, "Cannot post — amount is zero.")
        |> redirect(to: dp(conn, "/"))

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to post to GL. Check logs.")
        |> redirect(to: dp(conn, "/"))
    end
  end

  # ── Post ALL unposted costs to GL ──────────────────────────────

  def post_all_costs(conn, _params) do
    result = ExternalCostAccounting.post_all_unposted()

    msg = "Posted #{result.posted} costs to GL"
    msg = if result.skipped > 0, do: "#{msg}, #{result.skipped} skipped", else: msg
    msg = if result.errors > 0, do: "#{msg}, #{result.errors} errors", else: msg

    flash = if result.errors > 0, do: :error, else: :info

    conn
    |> put_flash(flash, msg <> ".")
    |> redirect(to: dp(conn, "/"))
  end

  # ── Bulk CSV upload ─────────────────────────────────────────────

  def bulk_upload_form(conn, _params) do
    render(conn, :bulk_upload, errors: nil, rows: nil, csv_preview: nil)
  end

  def bulk_upload_submit(conn, %{"upload" => %{"file" => %Plug.Upload{path: path}}}) do
    csv = File.read!(path)

    case DoctorPayoutImport.parse(csv) do
      {:ok, %{rows: rows}} ->
        case DoctorPayoutImport.commit(rows) do
          {:ok, count} ->
            conn
            |> put_flash(:info, "Recorded #{count} doctor payout(s) successfully.")
            |> redirect(to: dp(conn, "/doctor-payouts"))

          {:error, row, reason} ->
            ref = row && row.doctor_id
            msg = "Failed to record payout for doctor #{ref}: #{inspect(reason)}"

            conn
            |> put_flash(:error, msg)
            |> render(:bulk_upload, errors: [{0, msg}], rows: rows, csv_preview: csv)
        end

      {:error, %{rows: rows, errors: errors}} ->
        conn
        |> put_flash(:error, "CSV has #{length(errors)} issue(s). Nothing was saved.")
        |> render(:bulk_upload, errors: errors, rows: rows, csv_preview: csv)
    end
  end

  def bulk_upload_submit(conn, _params) do
    conn
    |> put_flash(:error, "Please choose a CSV file to upload.")
    |> redirect(to: dp(conn, "/doctor-payouts/bulk-upload"))
  end

  @doc """
  Returns a pre-filled CSV template based on the current per-doctor payout
  report so the user can edit amounts and re-upload.
  """
  def bulk_template(conn, params) do
    today = Ledgr.Domains.HelloDoctor.today()
    start_date = parse_date(params["start_date"]) || Date.beginning_of_month(today)
    end_date = parse_date(params["end_date"]) || today

    report = DashboardMetrics.doctor_payout_report(start_date, end_date)

    header = ["doctor_id", "doctor_name", "amount", "date", "description"]

    rows =
      Enum.map(report.rows, fn r ->
        [
          r.id,
          r.name,
          :erlang.float_to_binary(r.doctor_share + 0.0, decimals: 2),
          to_string(today),
          "Payout to #{r.name} — #{start_date} to #{end_date}"
        ]
      end)

    csv =
      [header | rows]
      |> Enum.map_join("", fn row ->
        row
        |> Enum.map(&csv_field/1)
        |> Enum.join(",")
        |> Kernel.<>("\r\n")
      end)

    filename = "doctor-payouts-template-#{start_date}-to-#{end_date}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, csv)
  end

  defp csv_field(v) when is_integer(v) or is_float(v), do: to_string(v)

  defp csv_field(v) when is_binary(v) do
    if String.contains?(v, [",", "\"", "\n", "\r"]) do
      ~s("#{String.replace(v, "\"", "\"\"")}")
    else
      v
    end
  end

  defp csv_field(other), do: csv_field(to_string(other))

  # ── Helpers ─────────────────────────────────────────────────────

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.DoctorPayoutHTML do
  use LedgrWeb, :html
  embed_templates "doctor_payout_html/*"
end
