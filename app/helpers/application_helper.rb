# app/helpers/application_helper.rb
module ApplicationHelper
  # --- Helper para saber si el usuario actual es superusuario ---
  # Lo usamos en vistas como: <% if is_superuser? %> ... <% end %>
  def is_superuser?
    current_user&.superuser? == true
  end

  # Renderiza la foto del cliente de forma robusta:
  # - Si hay procesador y la imagen es "variable", usa variant redimensionada y procesada.
  # - Si falla, renderiza el blob original.
  # - Si no hay foto, placeholder "Sin foto".
  #
  # size: lado en px (cuadrado)
  # classes: clases CSS extra
  def client_photo_tag(client, size: 144, classes: "")
    unless client&.photo&.attached?
      return content_tag(:div, "Sin foto", class: "client-photo ph #{classes}")
    end

    img = client.photo
    alt_text = client.name.presence || "Foto"

    begin
      if img.variable? && Rails.configuration.active_storage.variant_processor.present?
        return image_tag(
          img.variant(resize_to_fill: [ size, size ]).processed,
          class: "client-photo #{classes}",
          alt: alt_text
        )
      end
    rescue => e
      Rails.logger.warn("[client_photo_tag] variant failed: #{e.class}: #{e.message}")
    end

    image_tag img, class: "client-photo #{classes}", alt: alt_text, size: "#{size}x#{size}"
  end
end
