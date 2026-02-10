defmodule Mix.Tasks.ResetAccountingOnly do
  use Mix.Task

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting.{JournalLine, JournalEntry}

  @shortdoc "Deletes ALL journal entries and lines (accounting movements only)"

  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("\n⚠️  DELETING ALL ACCOUNTING MOVEMENTS (entries & lines) ⚠️\n")

    Repo.transaction(fn ->
      Repo.delete_all(JournalLine)
      Repo.delete_all(JournalEntry)
    end)

    IO.puts("\n✅ Accounting movements cleared (accounts, orders, inventory left intact)\n")
  end
end
