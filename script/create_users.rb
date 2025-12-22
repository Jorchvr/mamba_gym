# script/create_users.rb
# frozen_string_literal: true

puts "--- INICIO DE CREACIÓN DE USUARIOS ---"

# Lista basada en la imagen proporcionada
users_list = [
  # USUARIOS LIMITADOS
  { user: 'oscar.canul',   pass: 'oscar.canul',   role: 'limitado' },
  { user: 'mayel.arg',     pass: 'mayel.arg',     role: 'limitado' },
  { user: 'miguel.canul',  pass: 'miguel.canul',  role: 'limitado' },
  { user: 'yscar.tzap',    pass: 'yscar.tzap',    role: 'limitado' },
  { user: 'karla.dio',     pass: 'karla.dio',     role: 'limitado' },

  # SUPER USUARIOS
  { user: 'grissel.cohuo', pass: 'grissel.cohuo', role: 'super' },
  { user: 'yamil.vargas',  pass: 'yamil.vargas',  role: 'super' },
  { user: 'miguel.chuc',   pass: 'miguel.chuc',   role: 'super' },
  { user: 'elda.cohuo',    pass: 'elda.cohuo',    role: 'super' }
]

users_list.each do |u|
  # Como Devise pide email, les creamos uno falso con @powergym.com
  email = "#{u[:user]}@powergym.com"

  user = User.find_or_initialize_by(email: email)

  # Configuramos datos
  user.password = u[:pass]
  user.password_confirmation = u[:pass]

  # Intentamos guardar el nombre si tu base de datos tiene esa columna
  user.name = u[:user] if user.respond_to?(:name=)

  # Configurar permisos
  is_super = (u[:role] == 'super')

  if user.respond_to?(:superuser=)
    user.superuser = is_super
  end

  if user.save
    puts "✅ Creado: #{u[:user]} | Superusuario: #{is_super ? 'SÍ' : 'NO'}"
  else
    puts "❌ Error en #{u[:user]}: #{user.errors.full_messages.join(', ')}"
  end
end

puts "--- FIN ---"
