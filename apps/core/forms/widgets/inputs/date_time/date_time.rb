module Spider; module Forms
    
    class DateTime < Input
        tag 'datetime'
        is_attr_accessor :size, :type => Fixnum, :default => nil
        is_attr_accessor :mode, :type => Symbol, :default => :date
        i_attr_accessor :format, :type => String
        i_attr_accessor :lformat, :type => Symbol, :default => :short
        attribute :"change-month", :type => Spider::Bool, :default => false
        attribute :"change-year", :type => Spider::Bool, :default => false
        attribute :"past-dates", :type => Spider::Bool, :default => false
        attribute :"future-dates", :type => Spider::Bool, :default => false
        attribute :"year-range", :type => String, :default => "m150:p10"
        
        def prepare_value(val)
            
            return val if val.respond_to?(:strftime)
            return nil unless val.is_a?(String) && !val.empty?
            klass = case @mode
            when :date then Date
            when :time then Time
            else 
                ::DateTime
            end
            begin
                return klass.lparse(val, :short)
            rescue => exc
                add_error(_("%s is not a valid date") % val)
                return val
            end
        end
        
        def prepare
            unless @size
                @size = case @mode
                when :date then 10
                when :date_time then 15
                when :time then 8
                end
            end
            @additional_classes = []
            @additional_classes << 'change-month' if @attributes[:"change-month"]
            @additional_classes << 'change-year' if @attributes[:"change-year"]
            @additional_classes << 'past-dates' if @attributes[:"past-dates"]
            @additional_classes << 'future-dates' if @attributes[:"future-dates"]
            yr = @attributes[:"year-range"].sub('-', 'm').sub('+', 'p').sub(':', '-') if @attributes[:"change-year"]
            @additional_classes << "year-range-#{yr}" if yr 
            @scene.additional_classes = @additional_classes
            super
        end
        
        def format_value

            return '' unless @value
            if (@lformat && @value.respond_to?(:lformat))
                return @value.lformat(@lformat)
            elsif @format && @value.respond_to?(:strftime)
                return @value.strftime(@format)
            else
                return @value
            end
            return @value unless @value.respond_to?(:strftime)
            return @value.strftime("%d/%m/%Y %H:%M") if @value
            return ''
        end

    end
    
end; end