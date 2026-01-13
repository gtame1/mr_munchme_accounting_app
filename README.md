# MrMunchMeAccountingApp


## TODOs
- Unit economics - CHECK
- Cash flow - CHECK
- Add error handling to forms to any forms missing it
- Add purchase link to inventory
- Add notes to inventory purchases
- Add shorcut to shipping expense in inventory purchase form in case the purchase involves shipping/delivery expenses.
- Maybe: Split total inventory by inventory location
- Change all forms that accept cents to full pesos.
- Edit specific inventory used in each order. Some orders (few) use a bit more or a bit less inventory, or some might use more ingredients or less. How can we add something that can allow us to edit the order used inventory?
- Why is order status update so slow?
- What happens if i delete a customer with an active order? Do we need to catch that error?
- Should we add UI to add new balance sheet accounts?
- Add quantity to orders?
- Add "last 30 days"-type filters to the date filters in the dashboards.
- Move canceled orders out of the order list, maybe move to finished orders list or something like that?
- Fix bug when moving from existing->new->existing user glitches.
- Search feature for existing users.
- Check customer deposits, number doesnt sound right.
- Add functionality to "undo" or create a return of inventory. For example, whenever the user purchases inventory but then returns it. We should create the inventory movement and the accounting ledger.
- Add cutoff for when reconciliation was made in UI. Like "reconciled on x date" and show a line that divides the table or something like that.
- Fix how account balances are listed. Should be from newest to oldest and the balance should be updating as we move up.
- Manual: Fix inventory value.
- Add "all dates" button to all views that have a date filters. Use the same logic as the p&l button.

## Using github

- git status         # should show modified files
- git add .
- git commit -m "Tweak inventory purchase form"
- git push

## Database
`psql -d mr_munch_me_accounting_app_dev`