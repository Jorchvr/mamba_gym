# lib/tasks/import_clients_from_excel.rake
require "roo"

namespace :import do
  desc "Importa clientes desde Excel (IdCliente 1..1247)"
  task clients: :environment do
    xlsx_path = Rails.root.join("db", "data", "1_1Clientes-T10nov25(1).xlsx")

    unless File.exist?(xlsx_path)
      puts "No se encontró el archivo: #{xlsx_path}"
      exit 1
    end

    xlsx  = Roo::Spreadsheet.open(xlsx_path.to_s)
    sheet = xlsx.sheet(0)

    headers = sheet.row(1).map { |h| h.to_s.strip }

    idx_id_cliente        = headers.index("IdCliente")        && headers.index("IdCliente")        + 1
    idx_nombre            = headers.index("Cliente")          && headers.index("Cliente")          + 1
    idx_fecha_inscripcion = headers.index("FechaInscripcion") && headers.index("FechaInscripcion") + 1
    idx_id_pago           = headers.index("id_Pago")          && headers.index("id_Pago")          + 1

    if [idx_nombre, idx_fecha_inscripcion, idx_id_pago].any?(&:nil?)
      puts "No se encontraron las columnas necesarias (Cliente / FechaInscripcion / id_Pago)."
      puts "Encabezados detectados: #{headers.inspect}"
      exit 1
    end

    # Info de membership_type si es enum
    membership_enum = Client.defined_enums["membership_type"] || {}
    membership_keys = membership_enum.keys

    def map_membership_type_from_excel(tipo_pago_raw, membership_keys)
      return nil if membership_keys.blank?
      tipo = tipo_pago_raw.to_s.strip.upcase

      case tipo
      when /^MENSUAL/ # MENSUALIDAD, MENSUAL, etc
        %w[mensualidad mensual month monthly mes].find { |k| membership_keys.include?(k) }
      when /^SEMANA/
        %w[semana semanal week weekly].find { |k| membership_keys.include?(k) }
      when /^DIA/, /^DÍA/
        %w[dia día day diario daily].find { |k| membership_keys.include?(k) }
      else
        nil
      end
    end

    # Usuario por defecto si existe columna user_id con NOT NULL
    default_user_id = nil
    if Client.column_names.include?("user_id")
      default_user_id = Client.first&.user_id || User.first&.id
    end

    imported = 0
    errors   = 0

    # Limitar al rango de IdCliente 1..1247.
    # Asumimos que las filas están en orden y empiezan en la 2 (1 = encabezado).
    last_row = [sheet.last_row, 1248].min

    (2..last_row).each do |row_idx|
      id_cliente    = idx_id_cliente ? sheet.cell(row_idx, idx_id_cliente) : nil
      nombre        = sheet.cell(row_idx, idx_nombre)
      fecha_raw     = sheet.cell(row_idx, idx_fecha_inscripcion)
      tipo_pago_raw = sheet.cell(row_idx, idx_id_pago)

      # Solo clientes dentro del rango pedido
      if id_cliente && id_cliente.to_i > 1247
        next
      end

      # Saltar filas vacías
      if nombre.to_s.strip == "" || fecha_raw.nil? || tipo_pago_raw.to_s.strip == ""
        next
      end

      # Parsear fecha inscripción
      fecha_inscripcion =
        if fecha_raw.is_a?(Date) || fecha_raw.is_a?(Time)
          fecha_raw.to_date
        else
          begin
            Date.parse(fecha_raw.to_s)
          rescue
            puts "Fila #{row_idx} (IdCliente #{id_cliente}): fecha inválida #{fecha_raw.inspect}, se omite."
            errors += 1
            next
          end
        end

      tipo_pago = tipo_pago_raw.to_s.strip.upcase

      # Calcular fecha de vencimiento según tipo de pago
      next_payment_on =
        case tipo_pago
        when /^MENSUAL/
          fecha_inscripcion >> 1
        when /^SEMANA/
          fecha_inscripcion + 7
        when /^DIA/, /^DÍA/
          fecha_inscripcion + 1
        else
          # Tipo de pago desconocido → no rompemos, solo sin next_payment_on
          nil
        end

      attrs = {
        name: nombre.to_s.strip
      }

      attrs[:enrolled_on]     = fecha_inscripcion if Client.column_names.include?("enrolled_on")
      attrs[:next_payment_on] = next_payment_on   if next_payment_on && Client.column_names.include?("next_payment_on")
      attrs[:legacy_id]       = id_cliente.to_i   if id_cliente && Client.column_names.include?("legacy_id")

      # membership_type solo si es enum y encontramos match
      if Client.column_names.include?("membership_type") && membership_keys.present?
        mapped = map_membership_type_from_excel(tipo_pago, membership_keys)
        attrs[:membership_type] = mapped if mapped
      end

      # Buscar/crear por legacy_id si existe, si no por nombre+fecha
      client =
        if Client.column_names.include?("legacy_id") && id_cliente.present?
          Client.find_or_initialize_by(legacy_id: id_cliente.to_i)
        else
          base = { name: attrs[:name] }
          base[:enrolled_on] = attrs[:enrolled_on] if attrs[:enrolled_on]
          Client.find_or_initialize_by(base)
        end

      client.assign_attributes(attrs)

      # Asignar user_id por defecto si aplica
      if default_user_id && client.respond_to?(:user_id) && client.user_id.blank?
        client.user_id = default_user_id
      end

      begin
        # Forzamos guardar aunque haya validaciones de presencia de cosas que no tenemos
        client.save!(validate: false)
        imported += 1
        puts "OK fila #{row_idx}: #{client.name} | insc: #{fecha_inscripcion} | vence: #{next_payment_on}#{attrs[:membership_type] ? " | tipo: #{attrs[:membership_type]}" : ""}"
      rescue => e
        errors += 1
        puts "ERROR fila #{row_idx} (IdCliente #{id_cliente}, #{nombre}): #{e.class} - #{e.message}"
      end
    end

    puts "===================================="
    puts "Import terminado."
    puts "Clientes importados/actualizados: #{imported}"
    puts "Filas con error/omitidas:        #{errors}"
    puts "===================================="
  end
end
