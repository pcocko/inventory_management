require 'csv'
class InventoryController < ApplicationController

	unloadable

  after_filter :clear_xhr_flash

  def clear_xhr_flash
    if request.xhr?
      # Also modify 'flash' to other attributes which you use in your common/flashes for js
      flash.discard
    end
  end

  def reports
    @warehouses = InventoryWarehouse.order("name ASC").all.map {|w| [w.name, w.id]}
    @warehouses += [l('all_warehouses')]
    
    unless params[:warehouse]
      params[:warehouse] = l('all_warehouses')
    end
  end
  
  def report_export
    unless params[:id]
      params[:id] = nil
    end
    
    add = ""
    unless params[:warehouse]
      params[:warehouse] = l('all_warehouses')
    end
    
    if params[:warehouse] != l('all_warehouses')
      add = " AND warehouse_to_id = #{params[:warehouse]}"
    else
      add = " AND warehouse_to_id is not null"
    end
    
    if params[:id] == "input_invoice"
      @movements = InventoryMovement.where("document is not null and document != '' and document_type <= 3"+add).order('document ASC')
      
      headers = [l(:From),l(:field_document),l(:field_document_type),l(:field_category),l(:field_short_part_number),
        l(:field_serial_number), l(:field_squantity), l(:field_value),l(:total),l(:Date)]
      fields = []
      @movements.each do |m|
        from = nil
        if m.user_from_id
          from = User.find(m.user_from_id).login
        elsif m.inventory_providor
          from = m.inventory_providor.name
        elsif m.warehouse_from_id
          from = InventoryWarehouse.find(m.warehouse_from_id).name
        end
        total = (m.quantity * m.value rescue 0)
        fields << [from, m.document, m.doctype, m.inventory_part.inventory_category.name, m.inventory_part.part_number, m.serial_number, m.quantity, m.value, total, m.date]
      end
      
      arrays = []
      arrays[0] = headers
      arrays[1] = fields
        
      send_data(to_csv(arrays), :type => 'text/csv; header=present', :filename => 'in_movements_doc.csv')
    end
  end  
  

  def index
    @warehouses = InventoryWarehouse.order("name ASC").all.map {|w| [w.name, w.id]}
    @warehouses += [l('all_warehouses')]
    @statuses_array = ['',l('active'),l("obsolet"),l('discontinued'),l('unknown')]
    @property_array = ['','ADASA','ACA']

    add_in = ""
    add_out = ""
    unless params[:warehouse]
      params[:warehouse] = l('all_warehouses')
    end
    
    if params[:warehouse] != l('all_warehouses')
      add_in = " AND (`inventory_movements`.`warehouse_to_id` = #{params[:warehouse]})"
      add_out = " AND (`inventory_movements`.`warehouse_from_id` = #{params[:warehouse]})"
      params[:warehouse] = params[:warehouse].to_i
    end
    @stock = get_stock(add_in, add_out)
  end
  
  def get_stock(warehouse_query_in, warehouse_query_out)
    sql = ActiveRecord::Base.connection()
    @stock = sql.execute(
    "SELECT in_movements.part_number as part_number,
    	in_movements.serial_number as serial_number, in_movements.manufacturer as manufacturer, 
      in_movements.category as category,
    	in_movements.part_description as description, in_movements.warehouse_name, 
      in_movements.movement_warehouse_location, in_movements.movement_status, in_movements.movement_property,
      in_movements.value,
    	IFNULL(in_movements.quantity,0) as input,
    	IFNULL(out_movements.quantity,0) as output,
    	(IFNULL(in_movements.quantity,0)-IFNULL(out_movements.quantity,0)) as stock,
    	GREATEST(IFNULL(in_movements.last_date,0), IFNULL(out_movements.last_date,0)) as last_movement
    FROM
  		(SELECT `inventory_parts`.`id` as `part_id`, `inventory_parts`.`part_number` AS `part_number`, `inventory_movements`.`serial_number` AS `serial_number`,
          `inventory_parts`.`manufacturer` AS `manufacturer`,
          `inventory_warehouses`.`id` AS `warehouse_id`,
          `inventory_warehouses`.`name` AS `warehouse_name`,
          `inventory_movements`.`document` AS `movement_warehouse_location`,
          `inventory_movements`.`status` AS `movement_status`,
          `inventory_movements`.`property` AS `movement_property`,
      		`inventory_parts`.`value` AS `value`,sum(`inventory_movements`.`quantity`) AS `quantity`,
      		max(`inventory_movements`.`date`) AS `last_date`
      	FROM (`inventory_parts`
          LEFT JOIN `inventory_movements` on((`inventory_movements`.`inventory_part_id` = `inventory_parts`.`id`))
          LEFT JOIN `inventory_warehouses` on((`inventory_movements`.`warehouse_from_id` = `inventory_warehouses`.`id`))
          LEFT JOIN `inventory_categories` on((`inventory_categories`.`id` = `inventory_parts`.`inventory_category_id`)))
            WHERE (`inventory_movements`.`type_movement` = 2)"+warehouse_query_out+"              
                GROUP BY `inventory_parts`.`id`,`inventory_movements`.`serial_number`, `inventory_movements`.`document`, `inventory_movements`.`status`,
                         `inventory_warehouses`.`name`, `inventory_movements`.`property`, `inventory_warehouses`.`id`
                ORDER BY `inventory_parts`.`part_number`) as out_movements
        RIGHT JOIN
  				(SELECT `inventory_parts`.`id` as `part_id`, `inventory_parts`.`part_number` AS `part_number`, `inventory_categories`.`name` AS `category`,`inventory_parts`.`description` AS `part_description`,`inventory_movements`.`serial_number` AS `serial_number`,
              `inventory_parts`.`manufacturer` AS `manufacturer`, 
              `inventory_warehouses`.`id` AS `warehouse_id`,
              `inventory_warehouses`.`name` AS `warehouse_name`,
              `inventory_movements`.`document` AS `movement_warehouse_location`,
              `inventory_movements`.`status` AS `movement_status`,
              `inventory_movements`.`property` AS `movement_property`,
      				`inventory_parts`.`value` AS `value`,sum(`inventory_movements`.`quantity`) AS `quantity`,
      				max(`inventory_movements`.`date`) AS `last_date`
        		FROM (`inventory_parts`
          		LEFT JOIN `inventory_movements` on((`inventory_movements`.`inventory_part_id` = `inventory_parts`.`id`))
              LEFT JOIN `inventory_warehouses` on((`inventory_movements`.`warehouse_to_id` = `inventory_warehouses`.`id`))
          		LEFT JOIN `inventory_categories` on((`inventory_categories`.`id` = `inventory_parts`.`inventory_category_id`)))
            		WHERE (`inventory_movements`.`type_movement` = 1)"+warehouse_query_in+"
              		GROUP BY `inventory_parts`.`id`,`inventory_movements`.`serial_number`, `inventory_movements`.`document`, `inventory_movements`.`status`, 
                           `inventory_warehouses`.`name`, `inventory_movements`.`property`, `inventory_warehouses`.`id`
              		ORDER BY `inventory_parts`.`part_number`) as in_movements
        ON
          (out_movements.part_id = in_movements.part_id AND
           out_movements.movement_status = in_movements.movement_status AND
           out_movements.warehouse_id = in_movements.warehouse_id AND
           out_movements.movement_property = in_movements.movement_property)
        ORDER BY category, part_number;")
    return @stock
  end
  
  def to_csv(arrays)   
    decimal_separator = l(:general_csv_decimal_separator)
    
    export = CSV.generate(:col_sep => ";") do |csv|
    	csv << arrays[0] #.collect {|header| begin; header.to_s; rescue; header.to_s; end }
    	arrays[1].each do |row|
      	0.upto(row.length-1) do |i|
          if row[i].is_a?(Numeric)
            row[i] = row[i].to_s.gsub('.', decimal_separator)
          end
        end
        csv << row #.collect {|field| begin; field.to_s.encode("UTF-8"); rescue; field.to_s; end }
    	end
  	end
  	    
    return export
  end
  
  def inventory_stock_xls
    add = ""
    unless params[:warehouse]
      params[:warehouse] = l('all_warehouses')
    end
    
    if params[:warehouse] != l('all_warehouses')
      add = " AND (`inventory_movements`.`warehouse_from_id` = #{params[:warehouse]} OR " +
            "`inventory_movements`.`warehouse_to_id` = #{params[:warehouse]})"
      params[:warehouse] = params[:warehouse].to_i
    end
    @stock = get_stock(add)
    
    headers = [l(:field_short_part_number), l(:field_category), l(:field_description), l(:field_value),
                l(:inputs), l(:outputs),  l(:stock), l(:last_movement), l(:total)]
    fields = []
    total = 0
    @stock.each do |s|
      new_fields = [s[0],s[2],s[3],s[4],s[5],s[6],s[7],s[8],(s[4].to_f*s[7].to_f)]
      if s[1] and s[1].length > 0
        new_fields[0] << "(#{s[1]})"
      end
      total += s[4].to_f*s[7].to_f 
      fields << new_fields
    end
    fields << [nil,nil,nil,nil,nil,nil,nil,l(:total),total]
    
    arrays = []
    arrays[0] = headers
    arrays[1] = fields
    
    send_data(to_csv(arrays), :type => 'text/csv; header=present', :filename => 'inventory_stock.csv')
  end

  
  def ajax_get_part_value
    out = ''
    if params[:part_id]
      if part = InventoryPart.find(params[:part_id])
        out =  part.value.to_s
      end
    end
    render :text => out
  end
  
  def ajax_get_part_info
    out = []
    if params[:part_number]
      if part = InventoryPart.where("part_number = '"+params[:part_number]+"'").first
        out =  part.to_json
      end
    end
    render :json => out
  end

  def check_available_stock(movement)
    add_in = " AND (`inventory_movements`.`warehouse_to_id` = #{movement.warehouse_from_id} AND " +
            "`inventory_movements`.`inventory_part_id` = #{movement.inventory_part_id} AND " +
            "`inventory_movements`.`status` = #{movement.status} AND " +
            "`inventory_movements`.`property` = #{movement.property}) "
    add_out = " AND (`inventory_movements`.`warehouse_from_id` = #{movement.warehouse_from_id} AND " +
            "`inventory_movements`.`inventory_part_id` = #{movement.inventory_part_id} AND " +
            "`inventory_movements`.`status` = #{movement.status} AND " +
            "`inventory_movements`.`property` = #{movement.property}) "

    unless movement.serial_number.blank?
      add << " AND `inventory_movements`.`serial_number` = '#{movement.serial_number}'"
    end
    sql = ActiveRecord::Base.connection()
    
    @stock = sql.select_one("SELECT in_movements.part_number as part_number,
      in_movements.serial_number as serial_number, in_movements.manufacturer as manufacturer, 
      in_movements.category as category,
      in_movements.part_description as description, in_movements.warehouse_name, 
      in_movements.movement_warehouse_location, in_movements.movement_status, in_movements.movement_property,
      in_movements.value,
      IFNULL(in_movements.quantity,0) as input,
      IFNULL(out_movements.quantity,0) as output,
      (IFNULL(in_movements.quantity,0)-IFNULL(out_movements.quantity,0)) as stock,
      GREATEST(IFNULL(in_movements.last_date,0), IFNULL(out_movements.last_date,0)) as last_movement
    FROM
      (SELECT `inventory_parts`.`id` as `part_id`, `inventory_parts`.`part_number` AS `part_number`, `inventory_movements`.`serial_number` AS `serial_number`,
          `inventory_parts`.`manufacturer` AS `manufacturer`,
          `inventory_warehouses`.`id` AS `warehouse_id`,
          `inventory_warehouses`.`name` AS `warehouse_name`,
          `inventory_movements`.`document` AS `movement_warehouse_location`,
          `inventory_movements`.`status` AS `movement_status`,
          `inventory_movements`.`property` AS `movement_property`,
          `inventory_parts`.`value` AS `value`,sum(`inventory_movements`.`quantity`) AS `quantity`,
          max(`inventory_movements`.`date`) AS `last_date`
        FROM (`inventory_parts`
          LEFT JOIN `inventory_movements` on((`inventory_movements`.`inventory_part_id` = `inventory_parts`.`id`))
          LEFT JOIN `inventory_warehouses` on((`inventory_movements`.`warehouse_from_id` = `inventory_warehouses`.`id`))
          LEFT JOIN `inventory_categories` on((`inventory_categories`.`id` = `inventory_parts`.`inventory_category_id`)))
            WHERE (`inventory_movements`.`type_movement` = 2)"+add_out+"              
                GROUP BY `inventory_parts`.`id`,`inventory_movements`.`serial_number`, `inventory_movements`.`document`, `inventory_movements`.`status`,
                         `inventory_warehouses`.`name`, `inventory_movements`.`property`, `inventory_warehouses`.`id`
                ORDER BY `inventory_parts`.`part_number`) as out_movements
        RIGHT JOIN
          (SELECT `inventory_parts`.`id` as `part_id`, `inventory_parts`.`part_number` AS `part_number`, `inventory_categories`.`name` AS `category`,`inventory_parts`.`description` AS `part_description`,`inventory_movements`.`serial_number` AS `serial_number`,
              `inventory_parts`.`manufacturer` AS `manufacturer`, 
              `inventory_warehouses`.`id` AS `warehouse_id`,
              `inventory_warehouses`.`name` AS `warehouse_name`,
              `inventory_movements`.`document` AS `movement_warehouse_location`,
              `inventory_movements`.`status` AS `movement_status`,
              `inventory_movements`.`property` AS `movement_property`,
              `inventory_parts`.`value` AS `value`,sum(`inventory_movements`.`quantity`) AS `quantity`,
              max(`inventory_movements`.`date`) AS `last_date`
            FROM (`inventory_parts`
              LEFT JOIN `inventory_movements` on((`inventory_movements`.`inventory_part_id` = `inventory_parts`.`id`))
              LEFT JOIN `inventory_warehouses` on((`inventory_movements`.`warehouse_to_id` = `inventory_warehouses`.`id`))
              LEFT JOIN `inventory_categories` on((`inventory_categories`.`id` = `inventory_parts`.`inventory_category_id`)))
                WHERE (`inventory_movements`.`type_movement` = 1)"+add_in+"
                  GROUP BY `inventory_parts`.`id`,`inventory_movements`.`serial_number`, `inventory_movements`.`document`, `inventory_movements`.`status`, 
                           `inventory_warehouses`.`name`, `inventory_movements`.`property`, `inventory_warehouses`.`id`
                  ORDER BY `inventory_parts`.`part_number`) as in_movements
        ON
          (out_movements.part_id = in_movements.part_id AND
           out_movements.movement_status = in_movements.movement_status AND
           out_movements.warehouse_id = in_movements.warehouse_id AND
           out_movements.movement_property = in_movements.movement_property);")
    if @stock.present?
      return @stock['stock'].to_f #rescue 0
    else
      return 0
    end
    
  end

  def user_has_warehouse_permission(user_id, warehouse_id)
    if warehouse_id == nil
      if InventoryWarehouse.where('user_manager_id' => user_id.to_s).count > 0
        return true
      end
    else
      if InventoryWarehouse.where('user_manager_id = ? AND id = ?', user_id.to_s, warehouse_id.to_s).count > 0
        return true
      end
    end
    return false
  end
  

  def movements
    @parts = InventoryPart.order("part_number ASC").all.map {|p| [p.part_number + (p.manufacturer? ? ' - ' + p.manufacturer : '') + (p.description? ? ' - ' + p.description : ''),p.id]}
    @providors = InventoryProvidor.order("name ASC").all.map {|p| [p.name,p.id]}
    @inv_projects = Project.order('name ASC').all.map {|p| [p.name,p.id]}
    @users = User.where('status=1').order('lastname ASC, firstname ASC').map {|u| [u.lastname+" "+u.firstname, u.id]}
    @warehouses = InventoryWarehouse.order("name ASC").all.map {|w| [w.name, w.id]}
    @from_options_in = {l('User') => 'user_from_id', l('Providor') => 'inventory_providor_id'}
    @from_options = {l('User') => 'user_from_id', l('Warehouse') => 'warehouse_from_id', l('Providor') => 'inventory_providor_id'}
    @to_options = {l('User') => 'user_to_id', l('Project') => 'project_id',l('Warehouse') => 'warehouse_to_id'}
    @doc_types = { l('invoice') => 1, l('ticket') => 2, l('proforma-invoice') => 3, l("waybill") => 4, l("inventory") => 5}
    current_user = find_current_user
    @has_permission = current_user.admin? || user_has_warehouse_permission(current_user.id, nil)
    @statuses = { l('active') => 1, l("obsolet") => 2, l('discontinued') => 3, l('unknown') => 4}
    @statuses_array = ['',l('active'),l("obsolet"),l('discontinued'),l('unknown')]
    @property = { 'ADASA' => 1, 'ACA' => 2}    
    flash.discard

    unless params[:from_options]
      params[:from_options] = 'user_from_id'
    end
    
    unless params[:to_options]
      params[:to_options] = 'user_to_id'
    end
    
    if params[:delete]
      mdel = InventoryMovement.find(params[:delete]) rescue false
      if mdel
        if current_user.admin? or user_has_warehouse_permission(current_user.id, (mdel.warehouse_from_id != nil ? mdel.warehouse_from_id : 0)) or user_has_warehouse_permission(current_user.id, (mdel.warehouse_to_id != nil ? mdel.warehouse_to_id : 0))
          ok = InventoryMovement.delete(mdel) rescue false
          unless ok
            flash[:error] = l('cant_delete_register')
          end
        else
          flash[:error] = l('permission_denied')
        end
      end
    end
    
    if params[:edit_in]
      @inventory_in_movement = InventoryMovement.find(params[:edit_in])
      if @inventory_in_movement.user_from_id
        params[:from_options] = 'user_from_id'
      elsif @inventory_in_movement.inventory_providor
        params[:from_options] = 'inventory_providor_id'
      elsif @inventory_in_movement.warehouse_from_id
        params[:from_options] = 'warehouse_from_id'
      end
    else
      @inventory_in_movement = InventoryMovement.new
    end
    
    if params[:inventory_in_movement]
      if current_user.admin? or (user_has_warehouse_permission(current_user.id, params[:inventory_in_movement][:warehouse_to_id]) and (@inventory_in_movement.warehouse_to_id == nil ? true : user_has_warehouse_permission(current_user.id, @inventory_in_movement.warehouse_to_id)))
        unless params[:edit_in]
          @inventory_in_movement = InventoryMovement.new(params[:inventory_in_movement].permit!)
          
          available_stock = nil
          stock_ok = true
          if @inventory_in_movement.warehouse_from_id
          	available_stock = check_available_stock(@inventory_in_movement)
            logger.info "STOCK DISPONIBLE: "
            logger.info available_stock
            logger.info "movement.warehouse_from_id: "            
            logger.info @inventory_in_movement.warehouse_from_id
          	if @inventory_in_movement.quantity and @inventory_in_movement.quantity > available_stock
          		stock_ok = false
          	end
          end
          
          if stock_ok
          	@inventory_in_movement.user_id = current_user.id
          	@inventory_in_movement.date = DateTime.now
          	if @inventory_in_movement.save              
            	@inventory_in_movement = InventoryMovement.new(params[:inventory_in_movement].permit!)
            	@inventory_in_movement.inventory_part = nil
            	@inventory_in_movement.serial_number = nil
            	@inventory_in_movement.quantity = nil
            	@inventory_in_movement.value = nil
            	params[:create_in]  = true
          	end
          else
          	flash[:error] = l('out_of_stock')
          end
          
        else
          if @inventory_in_movement.update_attributes(params[:inventory_in_movement].permit!)
            params[:edit_in] = false
          end
        end
      else
        flash[:error] = l('permission_denied')
      end
    end
    
    if params[:edit_out]
      @inventory_out_movement = InventoryMovement.find(params[:edit_out])
      if @inventory_out_movement.user_from_id
        params[:to_options] = 'user_to_id'
      elsif @inventory_out_movement.inventory_providor
        params[:to_options] = 'project_id'
      elsif @inventory_out_movement.warehouse_to_id
        params[:to_options] = 'warehouse_to_id'
      end
    else
      @inventory_out_movement = InventoryMovement.new
    end
    
    if params[:inventory_out_movement]
      if current_user.admin? or (user_has_warehouse_permission(current_user.id, params[:inventory_out_movement][:warehouse_from_id]) and 
      (@inventory_out_movement.warehouse_from_id == nil ? true : user_has_warehouse_permission(current_user.id, @inventory_out_movement.warehouse_from_id)))
        unless params[:edit_out]
          @inventory_out_movement = InventoryMovement.new(params[:inventory_out_movement].permit!)
          available_stock = check_available_stock(@inventory_out_movement)
          if @inventory_out_movement.quantity and @inventory_out_movement.quantity <= available_stock
            @inventory_out_movement.user_id = current_user.id
            @inventory_out_movement.date = DateTime.now
            if @inventory_out_movement.save
              if @inventory_out_movement.warehouse_to_id
                @inventory_in_movement = InventoryMovement.new
                @inventory_in_movement.inventory_part_id = @inventory_out_movement.inventory_part_id
                @inventory_in_movement.quantity = @inventory_out_movement.quantity
                @inventory_in_movement.document = @inventory_out_movement.document
                @inventory_in_movement.document_type = @inventory_out_movement.document_type
                @inventory_in_movement.value = @inventory_out_movement.value
                @inventory_in_movement.warehouse_to_id = @inventory_out_movement.warehouse_to_id
                @inventory_in_movement.warehouse_from_id = @inventory_out_movement.warehouse_from_id
                @inventory_in_movement.property = @inventory_out_movement.property
                @inventory_in_movement.status = @inventory_out_movement.status
                @inventory_in_movement.type_movement = 1
                @inventory_in_movement.comments = ''
                @inventory_in_movement.user_id = current_user.id
                @inventory_in_movement.date = DateTime.now
                if @inventory_in_movement.save
                  logger.info "AQUI SE CREA EL MOVIMIENTO DE ENTRADA AL ALMACEN"          
                else
                  logger.info "ERROR!!!!!"
                  logger.info @inventory_in_movement.errors.full_messages
                end
              end
              @inventory_out_movement = InventoryMovement.new(params[:inventory_out_movement].permit!)
              @inventory_out_movement.inventory_part = nil
              @inventory_out_movement.serial_number = nil
              @inventory_out_movement.quantity = nil
              @inventory_out_movement.value = nil
              #@inventory_out_movement.comments = nil
              
              params[:create_out]  = true
            end
          else
            flash[:error] = l('out_of_stock')
          end
        else
          ok = true
          if @inventory_out_movement.quantity < params[:inventory_out_movement][:quantity].to_f
            available_stock = check_available_stock(@inventory_out_movement)
            unless (params[:inventory_out_movement][:quantity].to_f - @inventory_out_movement.quantity) <= available_stock
              ok = false
            end
          end
          if ok
            if @inventory_out_movement.update_attributes(params[:inventory_out_movement].permit!)
              params[:edit_out] = false
            end
          else
            flash[:error] = l('out_of_stock')
          end
        end
      else
        flash[:error] = l('permission_denied')
      end
    end

    @movements_in = InventoryMovement.where("type_movement = 1").order("date DESC")
    @movements_out = InventoryMovement.where("type_movement = 2").order("date DESC")
  end

  
  
  def categories
    @inventory_category = InventoryCategory.new
    current_user = find_current_user
    @has_permission = current_user.admin? || user_has_warehouse_permission(current_user.id, nil)
    
    if params[:delete] or params[:edit] or params[:inventory_category]
      if @has_permission
        
        if params[:delete]
          ok = InventoryCategory.delete(params[:delete]) rescue false
          unless ok
            flash[:error] = l('cant_delete_register')
          end
        end
        
        if params[:edit]
          @inventory_category = InventoryCategory.find(params[:edit])
        else
          @inventory_category = InventoryCategory.new
        end
        
        if params[:inventory_category]
          @inventory_category.update_attributes(params[:inventory_category].permit!)
          if @inventory_category.save
            @inventory_category = InventoryCategory.new
            params[:edit] = false
            params[:create]  = false
          end
        end
        
      else
        flash[:error] = l('permission_denied')
      end
    end
    
    @categories = InventoryCategory.all
  end


    
  def parts
    @inventory_part  = InventoryPart.new
    @categories = InventoryCategory.order("name ASC").all.map {|c| [c.name,c.id]}
    @statuses = { l('active') => 1, l("obsolet") => 2, l('discontinued') => 3}
    @statuses_array = ['',l('active'),l("obsolet"),l('discontinued')]
    current_user = find_current_user
    @has_permission = current_user.admin? || user_has_warehouse_permission(current_user.id, nil)
    if params[:delete] or params[:edit] or params[:inventory_part]
      if @has_permission
    
        if params[:delete]
          ok = InventoryPart.delete(params[:delete]) rescue false
          unless ok
            flash[:error] = l('cant_delete_register')
          end
        end
        
        if params[:edit]
          @inventory_part = InventoryPart.find(params[:edit])
        else
          @inventory_part = InventoryPart.new
        end
        
        if params[:inventory_part]
          @inventory_part.update_attributes(params[:inventory_part].permit!)
          if @inventory_part.save
            @inventory_part = InventoryPart.new
            params[:edit] = false
            params[:create]  = false
          end
        end
        
      else
        flash[:error] = l('permission_denied')
      end
    end
    @parts = InventoryPart.all
  end
  
  def providors
    @inventory_providor = InventoryProvidor.new
    current_user = find_current_user
    @has_permission = current_user.admin? || user_has_warehouse_permission(current_user.id, nil)
    if params[:delete] or params[:edit] or params[:inventory_providor]
      if @has_permission
        
        if params[:delete]
          ok = InventoryProvidor.delete(params[:delete]) rescue false
          unless ok
            flash[:error] = l('cant_delete_register')
          end
        end
        
        if params[:edit]
          @inventory_providor = InventoryProvidor.find(params[:edit])
        else
          @inventory_providor = InventoryProvidor.new
        end
        
        if params[:inventory_providor]
          @inventory_providor.update_attributes(params[:inventory_providor].permit!)
          if @inventory_providor.save
            @inventory_providor = InventoryProvidor.new
            params[:edit] = false
            params[:create]  = false
          end
        end
        
      else
        flash[:error] = l('permission_denied')
      end
    end
    
    
    @providors = InventoryProvidor.all
  end
  
  def warehouses
    @inventory_warehouse = InventoryWarehouse.new
    @users = User.where('status=1').order('lastname ASC, firstname ASC').map{|u| [u.lastname+" "+u.firstname, u.id]}
    @has_permission = find_current_user.admin?
    if params[:delete] or params[:edit] or params[:inventory_warehouse]
      if @has_permission
        if params[:delete]
          ok = InventoryWarehouse.delete(params[:delete]) rescue false
          unless ok
            flash[:error] = l('cant_delete_register')
          end
        end
        
        if params[:edit]
          @inventory_warehouse = InventoryWarehouse.find(params[:edit])
        else
          @inventory_warehouse = InventoryWarehouse.new
        end
          
        if params[:inventory_warehouse]
          @inventory_warehouse.update_attributes(params[:inventory_warehouse].permit!)
          if @inventory_warehouse.save
            @inventory_warehouse = InventoryWarehouse.new
            params[:edit] = false
            params[:create]  = false
          end
        end
      else
        flash[:error] = l('permission_denied')
      end
    end
    
    @warehouses = InventoryWarehouse.all
  end

end
