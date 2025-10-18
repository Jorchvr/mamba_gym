# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  before_action :enforce_boot_session
  before_action :configure_permitted_parameters, if: :devise_controller?

  helper_method :two_factor_ok?

  # --- Navegación tras login/logout ---
  def after_sign_in_path_for(resource)
    stored_location_for(resource) || authenticated_root_path
  end

  def after_sign_out_path_for(_resource_or_scope)
    session.delete(:superuser_code_ok)
    new_user_session_path
  end

  # === 2FA desactivado: devolvemos true y no bloqueamos nada ===
  def two_factor_ok?
    true
  end

  def require_two_factor!
    # No-op: dejamos pasar siempre
    true
  end

  private

  def require_superuser!
    unless current_user&.superuser?
      redirect_to authenticated_root_path, alert: "No autorizado."
    end
  end

  def enforce_boot_session
    boot_id = Rails.application.config.x.boot_id
    sess_boot = session[:boot_id]

    if sess_boot.nil?
      session[:boot_id] = boot_id
      return
    end

    if sess_boot != boot_id
      sign_out(current_user) if user_signed_in?
      reset_session
      redirect_to new_user_session_path
    end
  end

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up,        keys: [ :name, :superuser ])
    devise_parameter_sanitizer.permit(:account_update, keys: [ :name, :superuser ])
  end
end
