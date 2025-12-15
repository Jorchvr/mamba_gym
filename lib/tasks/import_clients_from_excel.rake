# /mnt/c/Users/ramoo/OneDrive/Documents/gym_control/script/import_clients_from_excel.rb
require "roo"

# ==========================================================
# 🚨 CONFIGURACIÓN NECESARIA
# ==========================================================
# Asigna el ID del usuario existente al que se asociarán todos los clientes importados.
# **DEBES ASEGURARTE DE QUE ESTE ID EXISTA EN TU TABLA DE 'users'**
DEFAULT_USER_ID = 1
# ==========================================================

file_path = "C:/Users/ramoo/OneDrive/Documents/clientes/clientes_nuevo.xlsx"

unless File.exist?(file_path)
  puts "❌ No se encontró el archivo: #{file_path}"
  exit
end

puts "✅ Clientes importados se asignarán al User ID: #{DEFAULT_USER_ID}"
puts "📂 Abriendo archivo Excel..."

xlsx = Roo::Excelx.new(file_path)
sheet = xlsx.sheet(0)

headers = sheet.row(1)

idx = {
  id_cliente: headers.index("IdCliente"),
  nombre: headers.index("Cliente"),
  tipo_pago: headers.index("id_Pago"),
  fecha_inscripcion: headers.index("FechaInscripcion")
}

if idx.values.any?(&:nil?)
  puts "❌ Error: falta una columna requerida en el Excel"
  puts "Se esperaban las columnas: IdCliente, Cliente, id_Pago, FechaInscripcion"
  puts "Índices encontrados: #{idx.inspect}"
  exit
end

puts "🧹 Eliminando clientes actuales..."
Client.delete_all

created = 0

puts "📥 Importando clientes..."

# Recorre todas las filas comenzando desde la segunda (i=2)
(2..sheet.last_row).each do |i|
  row = sheet.row(i)

  # Salta filas si no tienen ID de cliente o nombre
  next if row[idx[:id_cliente]].blank? || row[idx[:nombre]].blank?

  begin
    Client.create!(
      client_number: row[idx[:id_cliente]].to_s.strip,
      name: row[idx[:nombre]].to_s.strip,
      membership_type: row[idx[:tipo_pago]].to_s.strip.downcase,
      registered_at: row[idx[:fecha_inscripcion]],
      user_id: DEFAULT_USER_ID # <--- ¡SOLUCIÓN IMPLEMENTADA en este script!
    )
    created += 1
  rescue => e
    # Mostramos el error, pero el script se detendrá si es un error fatal (como NotNullViolation fuera de este rescue)
    puts "⚠️ Error al crear cliente en la fila #{i} (Nombre: #{row[idx[:nombre]]}): #{e.message}"
    next
  end
end

puts "✅ Importación finalizada"
puts "👥 Clientes importados: #{created}"
