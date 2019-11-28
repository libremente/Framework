module Spider; module Forms
    
    # Widget for managing forms.
    #
    # Attributes:
    # *:model*  model to use
    # *:elements*   array of elements to display
    # *:widget_types*   hash of widget classes to use for inputs
    # *:read_only*  array of read only elements
    # *:disabled*   array of disabled elements (will not be shown)
    # *:pk*     primary key element
    # *:save_submit_text*   text for the save button when updating
    # *:insert_submit_text* text for the save button when inserting
    # *:show_submit_and_new*    bool, whether to show the submit and new button (default: true)
    # *:show_submit_and_stay*   book, whether to show the submit and stay button (default: true)
    # *:submit_and_new_text*    text for the save and insert new button
    # *:submit_and_stay_text*   text for the submit and stay button
    #
    # Content:
    # replaces <form:input id="element_name" /> tags with appropriate inputs
    
    class Form < Spider::Widget
        tag 'form'
        is_attribute :form_action
        i_attr_accessor :model
        i_attr_accessor :elements
        i_attr_accessor :widget_types
        i_attribute :read_only
        i_attribute :disabled
        attribute :save_submit_text, :default => lambda{ 
            Spider::GetText.in_domain(Spider::Forms.gettext_domain) { _('Save')  } 
        }
        attribute :insert_submit_text, :default => lambda{ 
            Spider::GetText.in_domain(Spider::Forms.gettext_domain) { _('Insert')  } 
        }
        is_attribute :show_submit_and_new, :default => false
        is_attribute :show_submit_and_stay, :default => false
        is_attribute :show_additional_buttons, :default => false
        attribute :submit_and_new_text, :default => lambda{ _('%s and insert new') }
        attribute :submit_and_stay_text, :default => lambda{ _('%s and stay') }
        is_attr_accessor :pk
        attr_to_scene :inputs, :names, :hidden_inputs, :labels, :error, :errors, :sub_links
        attribute :show_related, :type => TrueClass, :default => false
        i_attribute :auto_redirect, :default => false
        is_attribute :multipart, :default => false
        is_attribute :form_css_class, :default => 'form-horizontal'
        attr_accessor :save_actions
        attr_accessor :fixed
        attr_accessor :before_save, :after_save
        
        attr_accessor :inputs
        attr_accessor :pk
        attr_reader :obj
        
        include Spider::EventSource
        
        def init
            @inputs = {}
            @names = []
            @hidden_inputs = []
            @errors = {}
            @labels = {}
            @save_actions ||= {}
            @sub_links = {}
            @disabled = []
            @read_only = []
            @requested_elements = []
            @obj = nil
        end
        
        def route_widget
            if (@action == :sub)
                [@crud.id, @_action.split('/', 3)[2]]
            end
        end
        
        def prepare(action='')
            @form_action = @request.path
            @pk ||= @_action_local
            @pk ||= params['pk']
            @pk = nil if @pk == 'new'
            @pk = Spider::HTTP.urldecode(@pk) if @pk && @pk.is_a?(String) && !@pk.empty?
            @model = const_get_full(@model) if @model.is_a?(String)
            if @model.method_defined?(:to_subclass) # FIXME: this is a quick hack, standardize
                @obj ||= load
                if @obj
                    @obj = @obj.to_subclass
                    @model = @obj.class
                end
            end
            @scene.model = @model
            if (@elements.is_a?(String))
                @elements = @elements.split(',').map{ |e| @model.elements[e.strip.to_sym] }.reject{ |i| i.nil? }
                @requested_elements = @elements
            end
            @elements = @model.elements_array unless @elements
            @model.each_element do |el|
                @labels[el.name] = el.label
            end
            #passo nome_elemento: full_class nella stringa
            #es tariffa: Spider::Forms::CheckboxList
            wt_string = @widget_types
            if @widget_types.is_a?(String)
                @widget_types = {}
                parts = wt_string.split(/\s*,\s*/)
                parts.each do |part|
                    el_id, class_name = part.split(/\s*:\s+/)
                    @widget_types[el_id] = class_name
                end
            end

            wt = @widget_types || {}
            @widget_types = {}
            wt.each do |key, value|
                value = const_get_full(value) if value.is_a?(String)
                @widget_types[key.to_sym] = value
            end
            if (@read_only.is_a?(String))
                @read_only = @read_only.split(',').map{ |el| el.strip.to_sym }
            end
            @read_only ||= []
            if (@disabled.is_a?(String))
                @disabled = @disabled.split(',').map{ |el| e.strip.to_sym }
            end
            @disabled ||= []
#            @data = params['data'] || {}
            if @_action_rest
                el_label, sub_rest = @_action_rest.split('/', 2)
                sub_rest ||= ''
                @sub_element = @elements.find{ |el| el.label.downcase.gsub(/\s+/, '_') == el_label}
            end
            if (@sub_element)
                @action = :sub
                @scene.sub_element = @sub_element
                @_pass_action = sub_rest
            else
                @action = :form
            end
            @scene.action = @action
            if (@attributes[:show_additional_buttons])
                @attributes[:show_submit_and_new] = true
                @attributes[:show_submit_and_stay] = true
            end
            if (params['submit_and_new'])
                @submit_action = 'submit_and_new'
            elsif (params['submit_and_stay'])
                @submit_action = 'submit_and_stay'
            else
                @submit_action = params['submit']
            end
            @obj ||= load
            @scene.obj = @obj
            init_widgets
            # if (@submit_action)
            # else
            if @obj
                @fixed.each {|k, v| @obj.set(k, v)} if (@fixed)
                set_values(@obj) if @action == :form && !@submit_action
            end
#            end
            super
            save(@submit_action) if @submit_action
        end
        
        def load_widgets(template=@template)
            super
            if (@action == :sub)
                @crud = Spider::Components::Crud.new(@request, @response)
                @crud.id = "crud_#{@sub_element.name.to_s}"
                @crud.model = @sub_element.model
                add_widget(@crud)
                @scene.crud = @crud
                @obj = load
                cond = {}
                if @sub_element.integrated?
                    @sub_element.integrated_from.model.primary_keys.each do |key|
                        cond[@sub_element.reverse.to_s+'.'+key.name.to_s] = @obj.get("#{@sub_element.integrated_from.name}.#{key.name}")
                    end
                else
                    @model.primary_keys.each do |key|
                        cond[@sub_element.reverse.to_s+'.'+key.name.to_s] = @obj.get(key)
                    end
                end
                @crud.fixed = cond
                sub_elements = []
                #sub_elements += @sub_element.model.primary_keys.map{ |k| k.name }
                @sub_element.model.elements_array.each do |el|
                    sub_elements << el.name unless el.integrated? || el.model == @model
                end
                @crud.attributes[:table_elements] = sub_elements
            else
                create_inputs
            end
        end
        
        def run
            #Spider::Logger.debug("FORM EXECUTING")
            if @obj && @pk
                @scene.form_desc = @model.label.downcase+' '+ (@obj.to_s || '')
                if (@action == :sub)
                    
                end
                @scene.submit_text = @attributes[:save_submit_text]
            else
                @scene.submit_text = @attributes[:insert_submit_text]
            end
            @scene.obj = obj
            Spider::GetText.in_domain(Spider::Forms.gettext_domain){
                @scene.submit_and_new_text = @attributes[:submit_and_new_text] % @scene.submit_text
                @scene.submit_and_stay_text = @attributes[:submit_and_stay_text] % @scene.submit_text
            }
            @scene.submit_buttons = @save_actions.keys
            @scene.enctype = 'multipart/form-data' if @multipart
            super
        end
        
        def create_inputs
            test_fixed = @model.new(@fixed) if @fixed
            @elements.each do |el|
                next if (el.hidden? && !@requested_elements.include?(el)) \
                    || el.autogenerated? || @disabled.include?(el.name)
                next if read_only?(el.name) && is_new?
                if @fixed
                    if (el.model?)
                        fixed_sub = test_fixed.get(el)
                        next if fixed_sub && fixed_sub.is_a?(Spider::Model::BaseModel) && fixed_sub.primary_keys_set?
                    else
                        next if test_fixed.element_has_value?(el)
                    end
                end
                @free_keys = true if el.primary_key?
                input = nil
                widget_type = nil
                if (@widget_types[el.name])
                    widget_type = @widget_types[el.name]
                elsif (el.type == String || el.type == Fixnum)
                    widget_type = Text
                    input_attributes = {:size => 5} if (el.type == Fixnum)
                    #aggiunto controllo su type ::Decimal per override metodi Decimal su Moduli per problemi con spazi ogni due cifre
                elsif (el.type == Float || el.type == BigDecimal || el.type == Spider::DataTypes::Decimal || ( el.type.respond_to?(:to_s) && !(el.type.to_s =~ /Decimal/).nil? ) )
                    widget_type = Text
                    input_attributes = {:size => 10}
                elsif (el.type == Spider::DataTypes::Text)
                    widget_type = TextArea
                elsif (el.type == ::DateTime || el.type == ::Date || el.type == ::Time)
                    widget_type = DateTime
                    input_attributes = {}
                    input_attributes[:mode] = case el.type.name
                    when 'DateTime' then :date_time
                    when 'Date' then :date
                    when 'Time' then :time
                    end
                elsif (el.type == Spider::DataTypes::TimeSpan)
                    widget_type = TimeSpan
                elsif (el.type == Spider::DataTypes::Password)
                    widget_type = Password
                elsif (el.type == Spider::DataTypes::Bool)
                    widget_type = Checkbox
                elsif (el.type == Spider::DataTypes::FilePath)
                    if el.attributes[:uploadable]
                        widget_type = FileInput
                        input_attributes = {:save_path => el.attributes[:base_path]}
                        input_attributes[:save_path] = input_attributes[:save_path].call if input_attributes[:save_path].is_a?(Proc)
                    else
                        widget_type = Text
                        input_attributes = {:size => 50}
                    end
                elsif (el.model?)
                    if ([:choice, :multiple_choice, :state, :multiple_state].include?(el.association) && !el.extended?)
                        widget_type = el.type.attributes[:estimated_size] && el.type.attributes[:estimated_size] > 30 ? 
                            SearchSelect : Select
                    elsif @attributes[:show_related] && @pk && el.multiple?
                        @sub_links[el.name] = sub_link(el)
                    end
                end
                input = create_input(widget_type, el) if widget_type
                
                #debug("Created input for #{el.name}, #{input}")
                if (input)
                    input.read_only if read_only?(el.name)
#                    input.id_path.insert(input.id_path.length-1, 'data')
                    if (input.is_a?(Hidden))
                        @hidden_inputs << input
                    else
                        @names << el.name
                    end
                    input.id = el.name
                    input.form = self
                    input.required = el.required?
#                    input.name = '_w'+param_name(input.id_path[0..-2]+['data']+input.id_path[-1..-1])
                    input.label = @labels[el.name]
                    @inputs[el.name] = input
                    if (input_attributes)
                        @widget_attributes[input.id] ||= {}
                        @widget_attributes[input.id] = input_attributes.merge(@widget_attributes[input.id])
                    end
                end
            end
        end
        
        def create_input(type, el)
            input = create_widget(type, el.name)
            input.css_classes << "el-#{el.name}"
            case type.name
            when 'Spider::Forms::Select', 'Spider::Forms::SearchSelect', 'Spider::Forms::CheckboxList'
                input.multiple = true if el.multiple? and type.name != 'Spider::Forms::CheckboxList'
                input.model = el.type if input.respond_to?(:model)
                input.condition = el.attributes[:choice_condition] || el.condition
            end
            @multipart = true if input.needs_multipart?
            if errs = @errors[el.name]
                while err = errs.pop
                    input.add_error(err)
                end
            end
            return input
        end
        
        def set_values(obj)
            @inputs.each do |element_name, input|
                #debug("SET VALUE #{obj.get(element_name)} ON INPUT #{input}, #{input.object_id}")
                input.value ||= obj.get(element_name)
            end
        end
        
        def instantiate_obj
            if (@pk && !@pk.to_s.empty?)
                parts = @pk.to_s.split(':')
                h = {}
                @model.primary_keys.each{ |k| h[k.name] = parts.shift }
                return @model.new(h)
            else
                return @model.new
            end
        end
        
        def load
            obj = instantiate_obj if (@pk)
            trigger(:after_load, obj)
            obj
        end
        
        def save(action=nil)
            obj = instantiate_obj
            obj.save_mode
            @save_actions[action].call(obj) if (action && @save_actions[action])
            inputs_done = true
            @elements.each do |el|
                break unless inputs_done
                element_name = el.name
                next if read_only?(element_name)
                
                input = @inputs[element_name]
                next unless input
                next if input.read_only?
                input.check
#                debug("SETTING #{element_name} TO #{@inputs[element_name].prepare_value(@data[element_name.to_s])}")
                if (input.error?)
                    @error = true
                    @errors[element_name] ||= []
                    @errors[element_name] += input.errors
                    next
                end
                next unless input.modified?
                begin
                    if (input.done?)
                        obj.set(element_name, (input.value.respond_to?(:force_encoding) ? input.value.force_encoding('UTF-8') : input.value ) ) 
                    else
                        inputs_done = false
                    end
#                    obj.set(element_name, @inputs[element_name].prepare_value(@data[element_name.to_s]))
                rescue FormatError => exc
                    add_error(exc.message, element_name, exc)
                rescue Spider::Model::NotUniqueError => exc
                    add_error(exc.message, element_name, exc)
                end
            end
            if (@fixed)
                obj.no_autoload do
                    @fixed.each do |k, v| 
                        obj.set!(k, v)
                    end
                end
            end
            if inputs_done && !@error
                if @free_keys
                    save_mode = obj.in_storage? ? :update : :insert
                else
                    save_mode = obj.primary_keys_set? ? :update : :insert
                end
                before_save(obj, save_mode)
                @before_save.call(obj, save_mode) if @before_save
                trigger(:before_save, obj)
            end
            if inputs_done && !@error
                begin
                    save_mode == :update ? obj.update : obj.insert
                    #debug("SAVED")
                    @saved = true
                    @pk = @model.primary_keys.map{ |k| obj[k.name] }.join(':')
                rescue => exc
                    if exc.is_a?(Spider::Model::MapperElementError)
                        Spider::Logger.error(exc)
                        exc_element =  exc.element.is_a?(Spider::Model::Element) ? exc.element.name : exc_element
                        add_error(exc.message, exc_element, exc)
                    else
                        raise
                    end
                end
                @after_save.call(obj, save_mode) if @after_save
                after_save(obj, save_mode)
                trigger(:save, obj, save_mode)
                @auto_redirect = true if @auto_redirect.is_a?(String) && @auto_redirect.strip == 'true'
                if @auto_redirect && !@error
                    if @auto_redirect.is_a?(String)
                        redirect(@auto_redirect)
                    else
                        redirect(@request.path)
                    end
                end
            end
            if (action == 'submit_and_new')
                @saved_and_new = true
            elsif (action == 'submit_and_stay')
                @saved_and_stay = true
            end
            @obj = obj
        end
        
        def before_save(obj, save_mode)
        end
        
        def after_save(obj, save_mode)
        end
        
        def add_error(message, element_name=nil, exception=nil)
            @error = true
            @errors[element_name] ||= []
            if @inputs[element_name]
                @inputs[element_name].add_error(message) 
            end
            @errors[element_name] << message
        end
        
        def is_new?
            @obj.nil?
        end
        
        def saved?
            @saved
        end
        
        def saved_and_new?
            @saved_and_new
        end
        
        def saved_and_stay?
            @saved_and_stay
        end
        
        def error?
            @error
        end
        
        def read_only?(element_name)
            @read_only.include?(element_name) || @model.elements[element_name].read_only?
        end
        
        def set_read_only(*names)
            @read_only += names
        end
        
        def disable(*names)
            @disabled += names
        end

        def breadcrumb
            bc = []
            if !@request.post? && @obj
                bc << {:label => @obj.to_s, :url => widget_request_path+'/'+@pk}
                if @crud
                    sl = sub_link(@sub_element)
                    bc << {:label => sl[:label], :url => widget_request_path+'/'+sl[:link] }
                    if @crud.action == :form
                        bc += @crud.form.breadcrumb
                    end
                end
            else
                bc << {:label => _('New'), :url => widget_request_path}
            end
            bc
            
        end

        def sub_link(el)
            {:link => @pk+'/'+el.label.downcase.gsub(/\s+/, '_'), :label => @labels[el.name]}
        end
        
        
        def self.parse_content(doc)
            overrides = []
            form_fields = doc.search('form:fields').to_a
            overrides += form_fields
            doc.search('form:fields').remove
            overrides.each{ |o| parse_override(o) }
            runtime, soverrides = super(doc)
            overrides += soverrides
            overrides.each do |ov|
                ov['search'] = '.fields' if (ov.name == 'tpl:inline-override')
            end
            if form_fields.length > 0
                inputs = []
                form_fields.each do |ff|
                    ff.search('sp:run').each do |run|
                        obj = run.get_attribute('obj')
                        if obj =~ /@inputs\[:(.+)\]/
                            inputs << $1
                        end
                    end
                end
                rtdoc = Hpricot::XML(runtime)
                if rtdoc.search("sp:attribute[@name=elements]").length < 1
                    rtdoc.root.innerHTML += "<sp:attribute name=\"elements\" value=\"#{inputs.join(',')}\" />"
                    runtime = rtdoc.to_s
                end
            end
            return [runtime, overrides]
        end
        
        def self.parse_override(el)
            if el.name == 'form:fields'
                el.name = 'tpl:override-content'
                el['search'] = '.fields'
            end
            el.search('form:input').each do |input|
                input_attributes = input.attributes.to_hash
                widget_id = input_attributes.delete('id')
                new_input = "<sp:run obj=\"@inputs[:#{widget_id}]\" widget=\":#{widget_id}\">"
                
                input_attributes.each do |key, value|
                    new_input += "<sp:attribute name=\"#{key}\" value=\"#{value}\" />"
                end
                new_input += "</sp:run>"
                input.swap(new_input)
            end
            return el
        end
        
        
    end
    
end; end
