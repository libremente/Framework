module Spider; module Forms
    
    class Checkbox < Input
        tag 'checkbox'
        
        def prepare_value(val)
            val = super
            return val ? true : false
        end

        def value
        	val = super
            return ( val.blank? ? false : true )
        end



    end
    
end; end