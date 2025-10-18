module ClientsHelper
  # Muestra la foto del cliente de forma robusta.
  # size: lado en px (cuadrado)
  # classes: clases extra de CSS
  def client_photo_tag(client, size: 144, classes: "")
    return content_tag(:div, "Sin foto", class: "client-photo ph #{classes}") unless client&.photo&.attached?

    # Intenta variante; si no hay image_processing/libvips, cae a la original.
    begin
      image_tag(
        client.photo.variant(resize_to_fill: [ size, size ]),
        class: "client-photo #{classes}",
        alt: client.name.presence || "Foto"
      )
    rescue
      image_tag(
        client.photo,
        class: "client-photo #{classes}",
        alt: client.name.presence || "Foto",
        size: "#{size}x#{size}"
      )
    end
  end
end
