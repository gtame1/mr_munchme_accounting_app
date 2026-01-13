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


## Using github

- git status         # should show modified file
- git add .
- git commit -m "Tweak inventory purchase form"
- git push

## Database
`psql -d mr_munch_me_accounting_app_dev`