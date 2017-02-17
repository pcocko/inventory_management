Redmine::Plugin.register :redmine_inventory_manager do
  name 'Redmine Inventory Manager Plugin'
  author 'Daniel Anguita O.'
  description 'Take your warehouse or office inventory on the same platform of your projects'
  version '0.9'
  url 'https://github.com/danielanguita/Redmine-Inventory-Manager'

  permission :inventory, {:inventory => [:index, :movements, :categories, :parts, :locations, :warehouses, :providors]}, :public => false

  permission :inventory_aca, {:inventory => [:index, :movements]}

  menu :top_menu, :inventory, { :controller => 'inventory', :action => 'index' }, :before => 'admin', :caption => 'Inventari', :if => Proc.new {User.current.logged? && User.current.allowed_to?(:inventory, nil, :global => true)}
  	
  settings :default => {'empty' => true}, :partial => 'settings/rim_settings'
end

