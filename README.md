# MrMunchMeAccountingApp


## TODOs
- Add error handling to forms to any forms missing it
- Add notes to inventory purchases
- Change all forms that accept cents to full pesos.
- Edit specific inventory used in each order. Some orders (few) use a bit more or a bit less inventory, or some might use more ingredients or less. How can we add something that can allow us to edit the order used inventory?
- Why is order status update so slow?
- What happens if i delete a customer with an active order? Do we need to catch that error?
- Should we add UI to add new balance sheet accounts?
- Fix bug when moving from existing->new->existing user glitches.
- Add cutoff for when reconciliation was made in UI. Like "reconciled on x date" and show a line that divides the table or something like that.
- Fix how account balances are listed. Should be from newest to oldest and the balance should be updating as we move up.
- Manual: Fix inventory value.


## Mix Tasks

### Diagnostic & Fix Tasks

#### Fix Withdrawal Accounts
Fixes historical withdrawal entries that incorrectly debited Owner's Equity (3000) instead of Owner's Drawings (3100).

```sh
MIX_ENV=prod mix fix_withdrawal_accounts           # Dry run - shows what would be fixed
MIX_ENV=prod mix fix_withdrawal_accounts --fix     # Apply the fix
```

#### Diagnose COGS
Diagnoses and fixes duplicate COGS journal entries caused by pattern matching issues.

```sh
MIX_ENV=prod mix diagnose_cogs           # Dry run - shows duplicates
MIX_ENV=prod mix diagnose_cogs --fix     # Remove duplicates
```

#### Backfill Movement Costs
Backfills costs for inventory movements that have $0 cost (useful when movements were recorded before purchases).

```sh
MIX_ENV=prod mix backfill_movement_costs
```

#### Repair Inventory Quantities
Recalculates and repairs inventory quantities from movements.

```sh
MIX_ENV=prod mix repair_inventory_quantities
```

#### Verify Inventory Accounting
Runs comprehensive integrity checks on inventory accounting (WIP balance, COGS consistency, etc.).

```sh
MIX_ENV=prod mix verify_inventory_accounting
```

### Reset Tasks (⚠️ DESTRUCTIVE)

#### Reset Accounting Only
Deletes ALL journal entries and lines (accounting movements only). Keeps accounts, orders, and inventory.

```sh
MIX_ENV=prod mix reset_accounting_only
```

#### Reset Inventory Only
Deletes ALL inventory movements and stock levels. Keeps ingredients and locations.

```sh
MIX_ENV=prod mix reset_inventory_only
```

#### Reset All Tables
Deletes data from ALL main tables (accounts, orders, inventory, partners, etc.).

```sh
MIX_ENV=prod mix reset_all_tables
```

#### Reset and Seed
Clears ALL data and reruns the seeds file.

```sh
MIX_ENV=prod mix reset_and_seed
```

#### Seed New Tables
Runs priv/repo/seeds.exs without clearing data (useful for adding new seed data).

```sh
MIX_ENV=prod mix seed_new_tables
```