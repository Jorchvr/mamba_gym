# script/ver_usuarios.rb
# frozen_string_literal: true

puts "===== 1. NOMBRES DE LAS COLUMNAS EN LA TABLA USERS ====="
# Esto nos dirá si tienes una columna llamada 'role', 'superuser', 'admin', etc.
puts User.column_names.join(', ')

puts "\n===== 2. LISTA DE USUARIOS EXISTENTES ====="
User.all.each do |u|
  # Imprimimos datos clave para ver cómo se diferencian
  puts "------------------------------------------------"
  puts "ID: #{u.id}"
  puts "Email: #{u.email}"
  puts "Nombre: #{u.try(:name) || 'Sin nombre'}"

  # Verificamos posibles columnas de permisos
  if u.respond_to?(:superuser)
    puts "Superuser: #{u.superuser.inspect}"
  end

  if u.respond_to?(:role)
    puts "Role: #{u.role.inspect}"
  end

  if u.respond_to?(:admin)
    puts "Admin: #{u.admin.inspect}"
  end
end
puts "------------------------------------------------"
puts "Total usuarios: #{User.count}"
