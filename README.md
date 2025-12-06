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
- Add inventory consolidation tool
- Add delivery calendar.
- Add shortcuts to update the order status or record a payment from the order index
- Modify the order payments:
    1) Add CRUD to the order payments. 
    2) I have one example where the sale amount was 420 and the customer payed 500, the difference was paid by a partner so those 80 should go to accounts payable to the partner, how can i simply this money movements registration?

## Using github

- git status         # should show modified file
- git add .
- git commit -m "Tweak inventory purchase form"
- git push