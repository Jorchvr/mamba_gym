require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module GymControl
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.

    # =========================================================
    # ✅ CONFIGURACIÓN DE ZONA HORARIA (MONTERREY / MÉXICO)
    # =========================================================
    config.time_zone = "Mexico City"

    # Esto asegura que Rails guarde en la BD en formato universal (UTC)
    # pero te muestre la hora correcta en tu pantalla automáticamente.
    config.active_record.default_timezone = :utc

    # Opcional: Configurar idioma predeterminado a Español
    config.i18n.default_locale = :es

    # config.eager_load_paths << Rails.root.join("extras")
  end
end
