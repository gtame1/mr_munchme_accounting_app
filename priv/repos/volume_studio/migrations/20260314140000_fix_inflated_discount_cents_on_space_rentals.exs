defmodule Ledgr.Repos.VolumeStudio.Migrations.FixInflatedDiscountCentsOnSpaceRentals do
  use Ecto.Migration

  @doc """
  Fixes space_rental records where discount_cents was stored 100× too large due
  to a double pesos→cents conversion bug.

  Safe heuristic: a discount can never exceed the total (base + IVA). If it does,
  the value was clearly inflated — divide by 100 to restore the correct cents value.
  """
  def up do
    execute """
    UPDATE space_rentals
    SET    discount_cents = discount_cents / 100
    WHERE  discount_cents > 0
      AND  discount_cents > (amount_cents + ROUND(amount_cents * 0.16))
    """
  end

  def down do
    execute """
    UPDATE space_rentals
    SET    discount_cents = discount_cents * 100
    WHERE  discount_cents > 0
      AND  (discount_cents * 100) > (amount_cents + ROUND(amount_cents * 0.16))
    """
  end
end
