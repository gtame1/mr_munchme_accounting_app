defmodule Ledgr.Repos.CasaTame.Migrations.ReplaceExpenseCategories do
  use Ecto.Migration

  @moduledoc """
  Replaces English expense account tree (6000–6105) with the Spanish
  category tree from the CSV budget design.

  Strategy:
  1. INSERT all new accounts with temporary 8xxx codes (avoids code collisions)
  2. UPDATE expenses.expense_account_id  old → new account ID
  3. UPDATE journal_lines.account_id     old → new account ID
  4. Catch-all: remaining old-code expenses → 8192 Uncategorized
  5. DELETE all old expense accounts (6000–6105)
  6. Rename new accounts from 8xxx → final 6xxx codes
  """

  def up do
    now = "NOW()"

    # ── Step 1: INSERT new accounts with temp 8xxx codes ─────────────────

    # Auto y Transporte (→ 6000–6008)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8000', 'Auto y Transporte', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8001', 'Gasolina', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8002', 'Estacionamiento', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8003', 'Seguro de Auto', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8004', 'Refacciones', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8005', 'Registro y Fees', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8006', 'Uber/Lyft', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8007', 'Transporte Publico', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8008', 'Compra de Coche', 'expense', 'debit', false, false, #{now}, #{now})"

    # Servicios (→ 6010–6018)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8010', 'Servicios', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8011', 'Telefono Fijo', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8012', 'Internet', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8013', 'Celulares', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8014', 'Television/Streaming', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8015', 'Luz', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8016', 'Agua', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8017', 'Gas', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8018', 'Basura y Reciclaje / Otros', 'expense', 'debit', false, false, #{now}, #{now})"

    # Casa (→ 6020–6031)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8020', 'Casa', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8021', 'Compra (Loan)', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8022', 'Anticipo', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8023', 'Costos de Cierre', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8024', 'Reserva', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8025', 'Muebles', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8026', 'Mudanza', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8027', 'Pago de Renta', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8028', 'HOA', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8029', 'Muchacha/Servicios', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8030', 'Mantenimiento', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8031', 'Impuestos y Fees (Casa)', 'expense', 'debit', false, false, #{now}, #{now})"

    # Educacion (→ 6040–6042)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8040', 'Educacion', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8041', 'Libros y Supplies', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8042', 'Colegiatura', 'expense', 'debit', false, false, #{now}, #{now})"

    # Entretenimiento (→ 6050–6055)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8050', 'Entretenimiento', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8051', 'Amusement', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8052', 'Arts', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8053', 'Movies & DVDs', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8054', 'Music', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8055', 'Newspapers & Magazines', 'expense', 'debit', false, false, #{now}, #{now})"

    # Comida y Restaurantes (→ 6060–6065)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8060', 'Comida y Restaurantes', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8061', 'Alcohol y Bares', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8062', 'Café', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8063', 'Fast Food/Uber Eats', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8064', 'Super', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8065', 'Restaurantes', 'expense', 'debit', false, false, #{now}, #{now})"

    # Salud y Deportes (→ 6070–6075)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8070', 'Salud y Deportes', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8071', 'Dentista', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8072', 'Doctor', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8073', 'Gym', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8074', 'Medicinas', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8075', 'Sports', 'expense', 'debit', false, false, #{now}, #{now})"

    # Seguro Medico (→ 6080–6083)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8080', 'Seguro Medico', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8081', 'Seguro Medico - Guillo', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8082', 'Seguro Medico - Ana Gaby', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8083', 'Seguro Medico - Alonso', 'expense', 'debit', false, false, #{now}, #{now})"

    # Cuidado Personal (→ 6090–6093)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8090', 'Cuidado Personal', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8091', 'Pelo', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8092', 'Lavanderias', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8093', 'Spa & Massage', 'expense', 'debit', false, false, #{now}, #{now})"

    # Hijos (→ 6100–6105)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8100', 'Hijos', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8101', 'Domingo', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8102', 'Baby Supplies', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8103', 'Babysitter & Daycare', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8104', 'Kids Activities', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8105', 'Toys', 'expense', 'debit', false, false, #{now}, #{now})"

    # Shopping (→ 6110–6116)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8110', 'Shopping', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8111', 'Books', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8112', 'Clothing', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8113', 'Electronics & Software', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8114', 'Hobbies', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8115', 'Sporting Goods', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8116', 'Shopping - Otros', 'expense', 'debit', false, false, #{now}, #{now})"

    # Viajes (→ 6120–6124)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8120', 'Viajes', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8121', 'Air Travel', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8122', 'Hotel', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8123', 'Rental Car & Taxi', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8124', 'Vacation', 'expense', 'debit', false, false, #{now}, #{now})"

    # Mascota (→ 6130–6134)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8130', 'Mascota', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8131', 'Mascota - Compra', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8132', 'Mascota - Comida', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8133', 'Veterinario', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8134', 'Cortes de pelo (Mascota)', 'expense', 'debit', false, false, #{now}, #{now})"

    # Intereses de Prestamos (→ 6140–6144)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8140', 'Intereses', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8141', 'Prestamo Coche', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8142', 'Prestamo Edu 1', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8143', 'Prestamo Edu 2', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8144', 'Mortgage', 'expense', 'debit', false, false, #{now}, #{now})"

    # Fees & Charges (→ 6150–6156)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8150', 'Fees & Charges', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8151', 'ATM Fee', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8152', 'Bank Fee', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8153', 'Finance Charge', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8154', 'Late Fee', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8155', 'Service Fee', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8156', 'Trade Commissions', 'expense', 'debit', false, false, #{now}, #{now})"

    # Financieros (→ 6160–6162)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8160', 'Financieros', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8161', 'Financial Advisor', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8162', 'Life Insurance', 'expense', 'debit', false, false, #{now}, #{now})"

    # Regalos y Donaciones (→ 6170–6172)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8170', 'Regalos y Donaciones', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8171', 'Donaciones', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8172', 'Regalos', 'expense', 'debit', false, false, #{now}, #{now})"

    # Impuestos (→ 6180–6182)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8180', 'Impuestos', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8181', 'Servicio de Impuestos', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8182', 'Impuesto por ganancias', 'expense', 'debit', false, false, #{now}, #{now})"

    # Otros (→ 6190–6192)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8190', 'Otros', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8191', 'Tip', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('8192', 'Uncategorized', 'expense', 'debit', false, false, #{now}, #{now})"

    # ── Step 2: Remap expense records (old code → best new equivalent) ────

    # Helper macro for remapping:
    # UPDATE expenses SET expense_account_id = (new) WHERE expense_account_id = (old)

    remap = fn old_code, new_code ->
      execute """
      UPDATE expenses
      SET expense_account_id = (SELECT id FROM accounts WHERE code = '#{new_code}')
      WHERE expense_account_id = (SELECT id FROM accounts WHERE code = '#{old_code}')
      """
    end

    # Auto y Transporte
    remap.("6000", "8000")   # Auto & Transportation → Auto y Transporte (group)
    remap.("6001", "8001")   # Gas & Fuel → Gasolina
    remap.("6002", "8002")   # Parking & Tolls → Estacionamiento
    remap.("6003", "8003")   # Car Insurance → Seguro de Auto
    remap.("6004", "8004")   # Car Maintenance → Refacciones
    remap.("6005", "8006")   # Ride Sharing → Uber/Lyft
    remap.("6006", "8141")   # Car Loan Payments → Prestamo Coche (Intereses)

    # Housekeeper & Drivers → Muchacha/Servicios (Casa Recurrentes)
    remap.("6010", "8029")   # Housekeeper & Drivers (group) → Muchacha/Servicios
    remap.("6011", "8029")   # Housekeeper Salary → Muchacha/Servicios
    remap.("6012", "8029")   # Driver / Chauffeur → Muchacha/Servicios

    # Utilities → Servicios / Casa
    remap.("6020", "8010")   # Utilities (group) → Servicios (group)
    remap.("6021", "8015")   # Electricity → Luz
    remap.("6022", "8016")   # Water → Agua
    remap.("6023", "8017")   # Gas (Home) → Gas
    remap.("6024", "8012")   # Internet & Phone → Internet
    remap.("6025", "8028")   # HOA / Condo Fees → HOA

    # Home & Furniture
    remap.("6030", "8030")   # Apartment Maintenance → Mantenimiento
    remap.("6031", "8030")   # Home Repairs → Mantenimiento
    remap.("6035", "8025")   # Furniture & Decor → Muebles
    remap.("6036", "8025")   # Appliances → Muebles

    # Education
    remap.("6040", "8040")   # Education (group) → Educacion (group)
    remap.("6041", "8042")   # Courses & Training → Colegiatura
    remap.("6042", "8041")   # Books & Materials → Libros y Supplies

    # Entertainment
    remap.("6050", "8050")   # Entertainment (group) → Entretenimiento (group)
    remap.("6051", "8014")   # Streaming & Subscriptions → Television/Streaming
    remap.("6052", "8051")   # Going Out & Events → Amusement
    remap.("6053", "8075")   # Hobbies & Sports → Sports

    # Food & Dining
    remap.("6060", "8062")   # Coffee Shops & Cafes → Café
    remap.("6061", "8064")   # Groceries & Supermarket → Super
    remap.("6062", "8063")   # Fast Food & Snacks → Fast Food/Uber Eats
    remap.("6063", "8065")   # Restaurants & Bars → Restaurantes
    remap.("6064", "8063")   # Food Delivery → Fast Food/Uber Eats

    # Health & Personal Care
    remap.("6070", "8080")   # Health Insurance (group) → Seguro Medico
    remap.("6071", "8090")   # Personal Care & Grooming → Cuidado Personal
    remap.("6072", "8072")   # Doctor & Specialist → Doctor
    remap.("6073", "8074")   # Pharmacy → Medicinas
    remap.("6074", "8071")   # Dental & Vision → Dentista
    remap.("6075", "8073")   # Gym & Fitness → Gym

    # Kids
    remap.("6080", "8100")   # Kids (group) → Hijos (group)
    remap.("6081", "8103")   # Daycare & School → Babysitter & Daycare
    remap.("6082", "8102")   # Kids Supplies → Baby Supplies
    remap.("6083", "8104")   # Activities & Toys → Kids Activities

    # Shopping
    remap.("6085", "8110")   # Shopping (group) → Shopping (group)
    remap.("6086", "8112")   # Clothing & Accessories → Clothing
    remap.("6087", "8113")   # Electronics & Gadgets → Electronics & Software

    # Travel
    remap.("6090", "8120")   # Travel (group) → Viajes (group)
    remap.("6091", "8121")   # Flights → Air Travel
    remap.("6092", "8122")   # Hotels & Lodging → Hotel
    remap.("6093", "8124")   # Travel Activities → Vacation

    # Pets
    remap.("6095", "8130")   # Pets (group) → Mascota (group)
    remap.("6096", "8132")   # Pet Food & Supplies → Mascota - Comida
    remap.("6097", "8133")   # Vet & Pet Health → Veterinario

    # Financial & Other
    remap.("6098", "8152")   # Bank & Financial Fees → Bank Fee
    remap.("6099", "8192")   # Other Expenses → Uncategorized
    remap.("6100", "8172")   # Gifts Given → Regalos
    remap.("6101", "8171")   # Donations & Charity → Donaciones
    remap.("6105", "8180")   # Taxes → Impuestos

    # ── Step 3: Remap journal_lines (same mappings) ──────────────────────

    remap_journal = fn old_code, new_code ->
      execute """
      UPDATE journal_lines
      SET account_id = (SELECT id FROM accounts WHERE code = '#{new_code}')
      WHERE account_id = (SELECT id FROM accounts WHERE code = '#{old_code}')
      """
    end

    for {old, new} <- [
      {"6000", "8000"}, {"6001", "8001"}, {"6002", "8002"}, {"6003", "8003"},
      {"6004", "8004"}, {"6005", "8006"}, {"6006", "8141"},
      {"6010", "8029"}, {"6011", "8029"}, {"6012", "8029"},
      {"6020", "8010"}, {"6021", "8015"}, {"6022", "8016"}, {"6023", "8017"},
      {"6024", "8012"}, {"6025", "8028"},
      {"6030", "8030"}, {"6031", "8030"}, {"6035", "8025"}, {"6036", "8025"},
      {"6040", "8040"}, {"6041", "8042"}, {"6042", "8041"},
      {"6050", "8050"}, {"6051", "8014"}, {"6052", "8051"}, {"6053", "8075"},
      {"6060", "8062"}, {"6061", "8064"}, {"6062", "8063"}, {"6063", "8065"}, {"6064", "8063"},
      {"6070", "8080"}, {"6071", "8090"}, {"6072", "8072"}, {"6073", "8074"},
      {"6074", "8071"}, {"6075", "8073"},
      {"6080", "8100"}, {"6081", "8103"}, {"6082", "8102"}, {"6083", "8104"},
      {"6085", "8110"}, {"6086", "8112"}, {"6087", "8113"},
      {"6090", "8120"}, {"6091", "8121"}, {"6092", "8122"}, {"6093", "8124"},
      {"6095", "8130"}, {"6096", "8132"}, {"6097", "8133"},
      {"6098", "8152"}, {"6099", "8192"}, {"6100", "8172"}, {"6101", "8171"}, {"6105", "8180"}
    ] do
      remap_journal.(old, new)
    end

    # ── Step 4: Safety net – any remaining old expense accounts → Uncategorized

    execute """
    UPDATE expenses
    SET expense_account_id = (SELECT id FROM accounts WHERE code = '8192')
    WHERE expense_account_id IN (
      SELECT id FROM accounts WHERE type = 'expense' AND code >= '6000' AND code <= '6199'
    )
    """

    execute """
    UPDATE journal_lines
    SET account_id = (SELECT id FROM accounts WHERE code = '8192')
    WHERE account_id IN (
      SELECT id FROM accounts WHERE type = 'expense' AND code >= '6000' AND code <= '6199'
    )
    """

    # Also update expense_splits if they reference expense accounts (they shouldn't, but just in case)
    execute """
    UPDATE expense_splits
    SET account_id = (SELECT id FROM accounts WHERE code = '8192')
    WHERE account_id IN (
      SELECT id FROM accounts WHERE type = 'expense' AND code >= '6000' AND code <= '6199'
    )
    """

    # ── Step 5: DELETE old expense accounts ───────────────────────────────

    execute "DELETE FROM accounts WHERE type = 'expense' AND code >= '6000' AND code <= '6199'"

    # ── Step 6: Rename 8xxx codes → final 6xxx codes ─────────────────────

    for {temp, final} <- [
      # Auto y Transporte
      {"8000", "6000"}, {"8001", "6001"}, {"8002", "6002"}, {"8003", "6003"},
      {"8004", "6004"}, {"8005", "6005"}, {"8006", "6006"}, {"8007", "6007"}, {"8008", "6008"},
      # Servicios
      {"8010", "6010"}, {"8011", "6011"}, {"8012", "6012"}, {"8013", "6013"}, {"8014", "6014"},
      {"8015", "6015"}, {"8016", "6016"}, {"8017", "6017"}, {"8018", "6018"},
      # Casa
      {"8020", "6020"}, {"8021", "6021"}, {"8022", "6022"}, {"8023", "6023"}, {"8024", "6024"},
      {"8025", "6025"}, {"8026", "6026"}, {"8027", "6027"}, {"8028", "6028"}, {"8029", "6029"},
      {"8030", "6030"}, {"8031", "6031"},
      # Educacion
      {"8040", "6040"}, {"8041", "6041"}, {"8042", "6042"},
      # Entretenimiento
      {"8050", "6050"}, {"8051", "6051"}, {"8052", "6052"}, {"8053", "6053"},
      {"8054", "6054"}, {"8055", "6055"},
      # Comida
      {"8060", "6060"}, {"8061", "6061"}, {"8062", "6062"}, {"8063", "6063"},
      {"8064", "6064"}, {"8065", "6065"},
      # Salud y Deportes
      {"8070", "6070"}, {"8071", "6071"}, {"8072", "6072"}, {"8073", "6073"},
      {"8074", "6074"}, {"8075", "6075"},
      # Seguro Medico
      {"8080", "6080"}, {"8081", "6081"}, {"8082", "6082"}, {"8083", "6083"},
      # Cuidado Personal
      {"8090", "6090"}, {"8091", "6091"}, {"8092", "6092"}, {"8093", "6093"},
      # Hijos
      {"8100", "6100"}, {"8101", "6101"}, {"8102", "6102"}, {"8103", "6103"},
      {"8104", "6104"}, {"8105", "6105"},
      # Shopping
      {"8110", "6110"}, {"8111", "6111"}, {"8112", "6112"}, {"8113", "6113"},
      {"8114", "6114"}, {"8115", "6115"}, {"8116", "6116"},
      # Viajes
      {"8120", "6120"}, {"8121", "6121"}, {"8122", "6122"}, {"8123", "6123"}, {"8124", "6124"},
      # Mascota
      {"8130", "6130"}, {"8131", "6131"}, {"8132", "6132"}, {"8133", "6133"}, {"8134", "6134"},
      # Intereses
      {"8140", "6140"}, {"8141", "6141"}, {"8142", "6142"}, {"8143", "6143"}, {"8144", "6144"},
      # Fees & Charges
      {"8150", "6150"}, {"8151", "6151"}, {"8152", "6152"}, {"8153", "6153"},
      {"8154", "6154"}, {"8155", "6155"}, {"8156", "6156"},
      # Financieros
      {"8160", "6160"}, {"8161", "6161"}, {"8162", "6162"},
      # Regalos y Donaciones
      {"8170", "6170"}, {"8171", "6171"}, {"8172", "6172"},
      # Impuestos
      {"8180", "6180"}, {"8181", "6181"}, {"8182", "6182"},
      # Otros
      {"8190", "6190"}, {"8191", "6191"}, {"8192", "6192"}
    ] do
      execute "UPDATE accounts SET code = '#{final}' WHERE code = '#{temp}'"
    end
  end

  def down do
    # Re-insert old English expense accounts and remap back
    # (Simplified: just clear new and re-run old migration)
    execute "DELETE FROM accounts WHERE type = 'expense' AND code >= '6000' AND code <= '6199'"
  end
end
