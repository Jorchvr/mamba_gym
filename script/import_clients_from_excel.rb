# frozen_string_literal: true

require 'spreadsheet'
require 'date'

# --- CONFIGURACIÓN ---
EXCEL_FILE_PATH = '/tmp/clientes_nuevo.xls'
DEFAULT_USER_ID = 1

# Nombres EXACTOS de los encabezados en tu Excel
HEADER_CLIENTE = 'Cliente'           # Columna del Nombre
HEADER_ID_PAGO = 'id_Pago'           # Columna del Plan
HEADER_FECHA   = 'FechaInscripcion'  # Columna de la Fecha
# ---------------------

# --- Funciones de Ayuda ---

def normalize_membership_type(raw_value)
  value = raw_value.to_s.strip.upcase
  case value
  when 'MENSUALIDAD', 'MES', 'MONTH' then 'month'
  when 'SEMANA', 'SEMANAL', 'WEEK'   then 'week'
  when 'DIA', 'DIARIO', 'VISITA', 'DAY' then 'day'
  else 'day'
  end
end

def normalize_date(raw_date)
  return nil if raw_date.blank? || raw_date.to_s.strip == 'FALSE'
  if raw_date.is_a?(Numeric)
    Date.new(1899, 12, 30) + raw_date.round.days rescue nil
  elsif raw_date.is_a?(Date) || raw_date.is_a?(Time)
    raw_date.to_date
  else
    Date.parse(raw_date.to_s) rescue nil
  end
end

# --- INICIO DEL SCRIPT ---

puts '--- INICIO DE IMPORTACIÓN DE CLIENTES ---'

unless File.exist?(EXCEL_FILE_PATH)
  puts "ERROR: No se encuentra el archivo en #{EXCEL_FILE_PATH}"
  exit
end

book = Spreadsheet.open(EXCEL_FILE_PATH)
sheet = book.worksheet(0)

# 1. ENCONTRAR ÍNDICES POR NOMBRE DE ENCABEZADO
header_row = sheet.row(0)
idx_nombre = nil
idx_plan   = nil
idx_fecha  = nil

header_row.each_with_index do |cell, index|
  val = cell.to_s.strip
  idx_nombre = index if val == HEADER_CLIENTE
  idx_plan   = index if val == HEADER_ID_PAGO
  idx_fecha  = index if val == HEADER_FECHA
end

if idx_nombre.nil? || idx_plan.nil? || idx_fecha.nil?
  puts "ERROR CRÍTICO: No se encontraron los encabezados correctos."
  exit
end

# 2. LIMPIEZA
puts 'Eliminando clientes anteriores y reiniciando IDs...'
Client.delete_all
ActiveRecord::Base.connection.reset_pk_sequence!('clients')

# 3. PROCESAMIENTO
puts "Procesando filas..."
created = 0
failed = 0

ActiveRecord::Base.transaction do
  sheet.each_with_index do |row, index|
    next if index == 0 # Saltar encabezado
    next if row.nil? || row.all?(&:nil?)

    nombre_raw = row[idx_nombre].to_s.strip
    next if nombre_raw.blank? # Saltar si no hay nombre

    # Normalizar datos
    final_membership = normalize_membership_type(row[idx_plan])
    final_enrolled_on = normalize_date(row[idx_fecha])

    # --- CALCULAR PRÓXIMO PAGO (LÓGICA AGREGADA) ---
    final_next_payment = nil

    if final_enrolled_on.present?
      final_next_payment = case final_membership
      when 'day'   then final_enrolled_on + 1.day
      when 'week'  then final_enrolled_on + 1.week
      when 'month' then final_enrolled_on + 1.month
      else              final_enrolled_on + 1.day
      end
    end
    # -----------------------------------------------

    begin
      Client.create!(
        client_number: nil, # Dejar que Rails asigne 1, 2, 3...
        name: nombre_raw,
        membership_type: final_membership,
        enrolled_on: final_enrolled_on,
        next_payment_on: final_next_payment, # <--- ¡AQUÍ ESTÁ LA SOLUCIÓN!
        user_id: DEFAULT_USER_ID
      )
      created += 1

      if created <= 5
        puts "  -> ID #{created}: #{nombre_raw} | Inscripción: #{final_enrolled_on} | Vence: #{final_next_payment}"
      end

    rescue => e
      failed += 1
      puts "  [ERROR] Fila #{index + 1} (#{nombre_raw}): #{e.message}"
    end
  end
end

puts "--- FIN ---"
puts "Clientes creados: #{created}"
puts "¡ÉXITO! Datos importados con fechas de pago calculadas."
