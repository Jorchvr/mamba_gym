class User < ApplicationRecord
  # Devise (sin :trackable)
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # “Enum” manual basado en entero: 0=normal, 1=superuser
  ROLE_NORMAL    = 0
  ROLE_SUPERUSER = 1

  def role_superuser?
    self[:role].to_i == ROLE_SUPERUSER
  end

  def role_normal?
    self[:role].to_i == ROLE_NORMAL
  end

  # Método universal que ya usas en vistas/controladores
  def superuser?
    return true if role_superuser?
    if respond_to?(:has_attribute?) && has_attribute?(:superuser)
      return ActiveModel::Type::Boolean.new.cast(self[:superuser])
    end
    false
  end

  # 🔴 IMPORTANTE: Eliminamos por completo el 2FA/código secreto:
  # - No hay attr_accessor :secret_code
  # - No hay validate :require_secret_code_for_superuser
  # - No existe el método require_secret_code_for_superuser
end
