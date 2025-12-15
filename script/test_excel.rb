require "roo"

path = "/mnt/c/Users/ramoo/OneDrive/Documents/clientes/clientes_nuevo.xlsx"

xlsx = Roo::Excelx.new(path)

sheet = xlsx.sheet(0)

puts "Filas totales: #{sheet.last_row}"
puts "Columnas totales: #{sheet.last_column}"

puts "Encabezados:"
puts sheet.row(1)
