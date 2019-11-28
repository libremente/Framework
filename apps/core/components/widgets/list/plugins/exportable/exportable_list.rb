module Spider; module Components
    
    module ExportableList
        include Spider::WidgetPlugin
        plugin_for List, 'exportable'
        
        __.action
        def export_to_csv
            @queryset.each do |row|
                $out << row.to_s+"\n"
            end
        end
        
        
    end
    
    
end; end