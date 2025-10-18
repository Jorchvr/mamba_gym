# db/seeds.rb

# Para dev/local: define un secreto si no viene por ENV (el modelo lo pide al
# convertir a superusuario).
ENV["SUPERUSER_SECRET"] ||= "0202"

def say(msg) = puts "→ #{msg}"

# Asegura que cualquier usuario existente tenga role != NULL (por si corres seeds en un proyecto viejo)
User.reset_column_information
if User.columns_hash.key?("role")
  fixed = User.where(role: nil).update_all(role: 0, updated_at: Time.current)
  say "Usuarios arreglados con role=NULL → role=0: #{fixed}"
end

# Helper idempotente para crear/actualizar usuarios
# role_int: 1 = superuser, 0 = normal
def upsert_user!(name:, email:, password:, role_int:)
  u = User.find_or_initialize_by(email: email)

  # **SIEMPRE** asigna role ANTES de guardar (evita NOT NULL)
  role_int = role_int.to_i
  u[:role] = role_int if u[:role].nil? || u[:role].to_i != role_int

  # Datos básicos
  u.name                  = name
  u.password              = password
  u.password_confirmation = password

  # Si será superusuario, pasa el secret_code para que pase la validación del modelo
  u.secret_code = ENV["SUPERUSER_SECRET"].to_s if role_int == 1

  u.save!
  u
end

# Usuarios de ejemplo (no uses estas contraseñas en producción)
yamil = upsert_user!(
  name:     "Yamil Vargas",
  email:    "yamil@example.com",
  password: "Yampiterparker2004@",
  role_int: 1
)
say "Superusuario: #{yamil.email} (role=#{yamil[:role]})"

jorge = upsert_user!(
  name:     "Jorge Vargas",
  email:    "jorge@example.com",
  password: "Gael7578@",
  role_int: 0
)
say "Usuario normal: #{jorge.email} (role=#{jorge[:role]})"

griselle = upsert_user!(
  name:     "Griselle",
  email:    "griselle@example.com",
  password: "PasswordSegura!123",
  role_int: 1
)
say "Superusuario: #{griselle.email} (role=#{griselle[:role]})"

puts "Seeds OK (SUPERUSER_SECRET=#{ENV['SUPERUSER_SECRET'].inspect})"
