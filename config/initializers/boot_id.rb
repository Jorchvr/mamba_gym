# Se crea un ID único por proceso/arranque de servidor
Rails.application.config.x.boot_id = SecureRandom.uuid
