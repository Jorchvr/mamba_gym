# lib/tasks/cleanup_clients.rake
namespace :cleanup do
  desc "Elimina clientes sin legacy_id (los creados manualmente antes del import)"
  task delete_old_clients: :environment do
    scope = Client.where(legacy_id: nil)

    puts "Clientes a eliminar: #{scope.count}"
    scope.order(:id).limit(50).pluck(:id, :name).each do |id, name|
      puts " - ##{id} #{name}"
    end

    # DESCOMENTA la línea de abajo cuando veas que la lista es la correcta
    # scope.destroy_all

    puts "Si la lista es correcta, edita esta tarea y descomenta scope.destroy_all para borrar definitivamente."
  end
end
