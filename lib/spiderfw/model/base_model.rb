# coding: UTF-8
# -*- encoding : utf-8 -*-
require 'spiderfw/model/mixins/state_machine'
require 'spiderfw/model/element'
require 'spiderfw/model/integrated_element'
require 'spiderfw/model/junction'
require 'iconv' if RUBY_VERSION =~ /1.8/

module Spider; module Model
    
    # @abtract
    # The main class for interacting with data.
    # When not dealing with legacy storages, subclasses should use Managed instead, which provides an id and 
    # other conveniences.
    #
    # Each BaseModel subclass defines a model; instances can be used as "data objects":
    # they will interact with the Mapper loading and saving the values associated with the BaseModel's defined elements.
    #
    # Each element defines an instance variable, a getter and a setter. If the instance is set to #autoload,
    # when a getter is first called the mapper will fetch the value from the Storage .
    #
    # Elements can be of one of the base types (Spider::Model.base_types), of a DataType, or other models. In the last
    # case, they define a relationship between models.
    # 
    # Basic usage:
    #   model Food < BaseModel
    #     element :name, String
    #   end
    #   model Animal < BaseModel
    #     element :name, String
    #     many :friends, Animal
    #     choice :favorite_food, Food
    #   end
    #   
    #   salmon = Food.new(:name => 'Salmon')
    #   salmon.save
    #   cat = Animal.new(:name => 'Cat', :favorite_food = salmon)
    #   weasel = Animal.new(:name => 'Weasel', :friends => [cat])
    #   weasel.save
    #   cat.friends << weasel
    #   cat.save
    #   
    #   wizzy = Animal.load(:name => 'Weasel')
    #   p wizzy.friends 
    #     => 'Cat'
    #   p wizzy.friends[0].favorite_food
    #     => 'Salmon'
    #
    #   bear = Animal.new(:name => 'Bear', :favorite_food = salmon)
    #   bear.save
    #   salmon_lovers = Animal.where{ favorite_food == salmon }
    #   p salmon_lovers.length
    #     => 2
    #   p salmon_lovers[0].name
    #     => 'Cat'
    class BaseModel
        include App::AppClass
        include Spider::Logger
        include DataTypes
        include Spider::QueryFuncs
        include EventSource
        # include StateMachine
        
        # The BaseModel class itself. Used when dealing with proxy objects.
        # @return [Class<BaseModel]
        attr_reader :model
        # An Hash of loaded elements
        # @return [Hash]
        attr_reader :loaded_elements
        # @private
        # Model instance or QuerySet containing the object
        # @return [BaseModel|QuerySet]
        attr_accessor :_parent
        # @private
        # If _parent is a model instance, which element points to this one
        # @return [Symbol]
        attr_accessor :_parent_element
        # @private
        # If true, forces the mapper to check for existance of the object in the storage
        # @return [bool]
        attr_accessor :_check_if_saved
        
        # @private
        # If this object is used as a superclass in class_table_inheritance, points to the current subclass
        # @return [Class<BaseModel]
        attr_accessor :_subclass_object
        # @private
        # This object won't be put into the identity mapper
        # @return [bool]
        attr_accessor :_no_identity_mapper
        # @private
        # Elements that were modified since a load or a save (note: this only keeps track of changed references on the object;
        # it doesn't consider if a associated object or QuerySet has changed. Use element_modified? to get that information)
        # @return [Array]
        attr_reader :_modified_elements
        
        class <<self
            # An Hash of model attributes. They can be used freely.
            # @return [Hash]
            attr_reader :attributes
            # An array of element names, in definition order.
            # @return [Array]
            attr_reader :elements_order
            # An Hash of integrated models => corresponding integrated element name.
            # @return [Hash]
            attr_reader :integrated_models
            # An Hash of polymorphic models => polymorphic params
            # @return [Hash]
            attr_reader :polymorphic_models
            # An Array of named sequences.
            # @return [Array]
            attr_reader :sequences
        end
        
        
        
        # Copies this class' elements to the subclass.
        # @param [Class<BaseModel] self
        # @return [void]
        def self.inherited(subclass) #:nodoc:
            # FIXME: might need to clone every element
            @subclasses ||= []
            @subclasses << subclass
            each_element do |el|
                unless el.attributes[:local_pk]
                    cl_el = el.clone
                    cl_el.definer_model = el.definer_model
                    subclass.add_element(cl_el) 
                end
            end
            subclass.instance_variable_set("@mapper_modules", @mapper_modules.clone) if @mapper_modules
            subclass.instance_variable_set("@extended_models", @extended_models.clone) if @extended_models
            em = subclass.const_set(:ElementMethods, Module.new)
            subclass.send(:include, em)
            super
        end
        
        # All known subclasses of this model
        # @return [Array]
        def self.subclasses
            @subclasses || []
        end
        
        
        #######################################
        #   Model definition methods          #
        #######################################
        
        # Defines an element.
        # Arguments are element name (a Symbol), element type, and a Hash of attributes.
        #
        # Type may be a Class: a base type (see Spider::Model.base_types), a DataType subclass, 
        # or a BaseModel subclass; or an Array or a Hash, in which case an InlineModel will be created.
        #
        # An Element instance will be available in Model::BaseModel.elements; getter and setter methods will be defined on
        # the class.
        #
        # If a block is passed to this method, type will be 'extended': a custom junction association will be created,
        # effectively adding elements to the type only in this model's context.
        # Example:
        #   class Animal < BaseModel
        #     element :name, String
        #     element :friends, Animal, :multiple => true do
        #       element :how_much, String
        #     end
        #   end
        #   cat = Animal.new(:name => 'Cat')
        #   dog = Animal.new(:name => 'Dog')
        #   cat.friends << dog
        #   cat.friend[0].how_much = 'Not very much'
        #
        # Returns the created Element.
        #
        # Some used attributes:
        # :primary_key::              (bool) The element is a primary key
        # :length::                   (number) Maximum length of the element (if meaningful)
        # :required::                 (bool) The element must always have a value
        # :multiple::                 (bool) defines a 1|n -> n relationship
        # :label::                    (string) a short description, used by the UI
        # :association::              (symbol) A named association (such as :choice, :multiple_choice, etc.)
        # :lazy::                     (bool, array or symbol) If true, the element will be placed in the :default lazy group;
        #                             if a symbol or an array of symbols is passed, the element will be placed in those groups.
        #                             (see Element#lazy_groups)
        # :reverse::                  (symbol) The reverse element in the relationship to the other model
        # :add_reverse::              (symbol) Adds an element on the other model, and sets it as the association reverse.
        # :add_multiple_reverse::     (symbol) Adds a multiple element on the other model, and sets it as the association reverse.
        # :element_position::         (number) inserts the element at the specified position in the elements order
        # :auto::                     (bool) Informative: the value is set automatically through some mechanism
        # :autoincrement::            (bool) The value (which must be a Fixnum) will be autoincremented by the mapper 
        # :integrate::                (bool or symbol) type's elements will be available to this class
        #                             as if they were defined here (see #integrate)
        # :integrated_from::          (symbol) the name of the element from which this element is integrated
        # :integrated_from_element::  (symbol) the name of the element of the child object from which this element is integrated
        # :hidden::                   (bool) a hint that the element shouldn't be shown by the UI
        # :computed_from::            (array of symbols) the element is not mapped; its value is computed
        #                             by the class from the given elements.
        # :unmapped::                 (bool) the element is not mapped.
        # :sortable::                 (bool or Array of symbols) specifies that an unmapped element can be used for sorting.
        #                             The model must provide a meaningful order using the prepare_query method.
        # :check::                    (a Proc, or a Regexp, or a Hash of messages => Regexp|Proc). See #check
        # :through::                  (a BaseModel subclass) model representing the many to many relationship.
        # :read_only::                (bool) hint to the UI that the element should not be user modifiable.
        # :owned::                    (bool) only this model holds references to type
        # :condition::                (hash or Condition) Restricts an association always adding the condition.
        # :order::                    (true or Fixnum) When doing queries, sort by this element. More than one element can have the
        #                             :order attribute; if it is a Fixnum, it will mean the position in the ordering.
        # :default::                  (Proc or value) default value for the element. If it is a Proc, it will be passed
        #                             the object.
        # :desc::                     (true or Fixnum) Use this element for the to_s string. Multiple elements
        #                             with the :desc attribute will be joined by spaces; order may be specified if 
        #                             a Fixnum is used for the parameter
        # 
        # Other attributes may be used by DataTypes (see #DataType::ClassMethods.take_attributes), and other code.
        # See also Element.
        # @yield If a block is given, will be called in the context of the junction model
        # @param [Symbol] name
        # @param [Class] type
        # @param [Hash] attributes
        # @return [Element]
        def self.element(name, type, attributes={}, &proc)
            name = name.to_sym
            @elements ||= {}
            @elements_order ||= []
            raise "Element called #{name} already exists in #{self}" if @elements[name]
            if type.class == Class
                default_attributes = case type.name
                when 'String'
                    {:length => 255}
                else
                    {}
                end
            else
                default_attributes = {}
            end
            attributes = default_attributes.merge(attributes)
            # if (type.class == Class && Model.base_type(type)) 
            #                 type = Model.base_type(type)
            #             els
            if (type.class <= Hash)
                type = create_inline_model(name, type, attributes)
                attributes[:inline] = true
            end
            if (attributes[:integrated_from])
                if (attributes[:integrated_from].class == String)
                    parts = attributes[:integrated_from].split('.')
                    attributes[:integrated_from] = @elements[parts[0].to_sym]
                    attributes[:integrated_from_element] = parts[1].to_sym if parts[1]
                elsif (attributes[:integrated_from].is_a?(Symbol))
                    attributes[:integrated_from] = @elements[attributes[:integrated_from]]
                end
                if (!attributes[:integrated_from_element])
                    attributes[:integrated_from_element] = name
                end
            end
            if (attributes[:condition] && !attributes[:condition].is_a?(Condition))
                attributes[:condition] = Condition.new(attributes[:condition])
            end
            if attributes[:computed_from] && !attributes[:computed_from].is_a?(Enumerable)
                attributes[:computed_from] = [attributes[:computed_from]]
            end
            attributes[:embedded] = true if attributes[:owned] && attributes[:embedded].nil?
            type.set_element_attributes(attributes) if type < Spider::DataType


            orig_type = type
            assoc_type = nil
            attributes[:reverse] ||= attributes[:reverse_of]
            if (proc || attributes[:junction] || (attributes[:multiple] && (!attributes[:add_reverse]) && (!attributes[:has_single_reverse]) && \
                # FIXME! the first check is needed when the referenced class has not been parsed yet 
                # but now it assumes that the reverse is not multiple if it is not defined
               (attributes[:has_single_reverse] == false || !attributes[:reverse] ||  (!type.elements[attributes[:reverse]] || type.elements[attributes[:reverse]].multiple?))))
                attributes[:anonymous_model] = true
                attributes[:owned] = true unless attributes[:owned] != nil
                first_model = self.first_definer(name, type)
                assoc_type_name = Spider::Inflector.camelize(name)
                create_junction = true
                if (attributes[:through])
                    assoc_type = attributes[:through]
                    create_junction = false
                elsif (first_model.constant_defined?(assoc_type_name) )
                    assoc_type = first_model.const_get(assoc_type_name)
                    if (assoc_type.respond_to?(:attributes) && !assoc_type.attributes[:sub_model]) # other kind of inline model
                        assoc_type_name += 'Junction'
                        create_junction = false if (first_model.const_defined?(assoc_type_name))
                    else
                        createP_junction = false
                    end
                end
                attributes[:junction] = true
                attributes[:junction_id] = :id unless attributes.has_key?(:junction_id)
                if (attributes[:junction_our_element])
                    self_name = attributes[:junction_our_element]
                else
                    self_name = first_model.short_name.gsub('/', '_').downcase.to_sym
                end
                attributes[:reverse] = self_name
                unless attributes[:junction_their_element]
                    other_name = Spider::Inflector.underscore(orig_type.short_name == self.short_name ? orig_type.name : orig_type.short_name).gsub('/', '_').downcase.to_sym
                    other_name = :"#{other_name}_ref" if (orig_type.elements[other_name])
                    attributes[:junction_their_element] = other_name
                end
                other_name = attributes[:junction_their_element]
                if (create_junction)
                    #evita il warning 'already initialized constant News' e 'already initialized constant Contents'
                    #if first_model.constant_defined?(assoc_type_name) 
                    #    return nil
                    #else
                        assoc_type = first_model.const_set(assoc_type_name, Class.new(BaseModel))
                    #end
                    assoc_type.attributes[:sub_model] = self
                    assoc_type.attributes[:sub_model_element] = name
                    embedder = attributes[:junction_embedded] == false ? false : true
                    assoc_type.element(attributes[:junction_id], Spider::DataTypes::PK, :primary_key => true, :autoincrement => true, :hidden => true) if attributes[:junction_id]
                    assoc_type.element(self_name, self, :hidden => true, :reverse => name, :association => :choice, :junction_reference => true, :embedder => embedder) # FIXME: must check if reverse exists?
                    # FIXME! fix in case of clashes with existent elements
                    assoc_type.element(other_name, orig_type, :association => :choice, :junction_reference => true, :embedded => attributes[:embedded])
                    assoc_type.integrate(other_name, :hidden => true, :no_pks => true) # FIXME: in some cases we want the integrated elements
                    assoc_type.send(:include, Spider::Model::Junction)
                    if (proc)                                   #        to be hidden, but the integrated el instead
                        attributes[:extended] = true
                        attributes[:keep_junction] = true
                        assoc_type.class_eval(&proc)
                    end
                end
                orig_type.referenced_by_junctions << [assoc_type, other_name]
                attributes[:keep_junction] = true if (attributes[:through] && attributes[:keep_junction] != false)
                attributes[:association_type] = assoc_type
                if attributes[:polymorph]
                    assoc_type.elements[attributes[:junction_their_element]].attributes[:polymorph] = attributes[:polymorph]
                    attributes.delete(:polymorph)
                end
                attributes[:embedded] = true unless attributes[:junction_embedded] == false
            end
            
            
            add_element(Element.new(name, type, attributes))
            
            
            if (attributes[:add_reverse] && attributes[:add_reverse].is_a?(Symbol))
                attributes[:add_reverse] = {:name => attributes[:add_reverse]}
            end
            if (attributes[:add_multiple_reverse] && attributes[:add_multiple_reverse].is_a?(Symbol))
                attributes[:add_multiple_reverse] = {:name => attributes[:add_multiple_reverse]}
            end
            
            if (attributes[:add_reverse])
                unless (orig_type.elements[attributes[:add_reverse]])
                    attributes[:reverse] ||= attributes[:add_reverse][:name]
                    rev = attributes[:add_reverse].merge(:reverse => name, :added_reverse => true, 
                        :delete_cascade => attributes[:reverse_delete_cascade])
                    rev_name = rev.delete(:name)
                    if assoc_type
                        rev[:junction] = true
                        rev[:keep_junction] = false
                        rev[:through] = assoc_type
                        rev[:junction_their_element] = self_name
                        rev[:junction_our_element] = other_name
                    end
                    if attributes[:embedded] && !attributes[:junction]
                        rev[:embedder] = true
                    end
                    orig_type.element(rev_name, self, rev)
                end
            elsif (attributes[:add_multiple_reverse])
                unless (orig_type.elements[attributes[:add_reverse]])
                    attributes[:reverse] ||= attributes[:add_multiple_reverse][:name]
                    rev = attributes[:add_multiple_reverse].merge(:reverse => name, :multiple => true, 
                        :added_reverse => true, :delete_cascade => attributes[:reverse_delete_cascade])
                    rev_name = rev.delete(:name)
                    if assoc_type
                        rev[:junction] = true
                        rev[:through] = assoc_type
                        rev[:junction_their_element] = self_name
                        rev[:junction_our_element] = other_name
                    end
                    orig_type.element(rev_name, self, rev)
                end
            end
            if (attributes[:lazy] == nil)
                # if attributes[:primary_key]
                #                     attributes[:lazy] = true
                #                 els
                if (type < BaseModel && (attributes[:multiple] || attributes[:polymorph]))
                    # FIXME: we can load eagerly single relations if we can do a join
                    attributes[:lazy] = true
                else
                    attributes[:lazy_check_owner] = true if type < BaseModel
                    attributes[:lazy] = :default
                end
            end
            
            

            
            # class element getter
            unless respond_to?(name)
                (class << self; self; end).instance_eval do
                    define_method("#{name}") do
                        @elements[name]
                    end
                end
            end
            
            define_element_methods(name)
            
            attr_reader "#{name}_junction" if attributes[:junction] && !attributes[:keep_junction]
            
            if (attributes[:integrate])
                integrate_params = attributes[:integrate].is_a?(Hash) ? attributes[:integrate] : {}
                integrate(name, integrate_params)
            end
            if self.attributes[:integrated_from_elements]
                self.attributes[:integrated_from_elements].each do |imod, iel|
                    imod.integrate_element(iel, self.elements[name]) unless imod.elements[name] || 
                        (self.elements[name].reverse == iel && self.elements[name].type == imod)
                end
            end
            if (@subclasses)
                @subclasses.each do |sub|
                    next if sub == type && attributes[:added_reverse] && sub.elements[attributes[:reverse]].type == self # subclass ref to parent
                    next if sub.elements[name] # if subclass already defined an element with this name, don't overwrite it
                    sub.elements[name] = @elements[name].clone
                    sub.elements_order << name
                end
            end
            element_defined(@elements[name])
            @elements[name].model?
            return @elements[name]

        end
        
        
        # @private
        # Helper method that defines getter and setter for an element
        # @param [Symbol] name Element name
        # @return [void]
        def self.define_element_methods(name)
            ivar = :"@#{ name }"

            unless self.const_defined?(:ElementMethods)
                em = self.const_set(:ElementMethods, Module.new)
                include em

            end
            element_methods = self.const_get(:ElementMethods)

            #instance variable getter
            element_methods.send(:define_method, name) do                
                element = self.class.elements[name]
                raise "Internal error! Element method #{name} exists, but element not found" unless element
                return element.attributes[:fixed] if element.attributes[:fixed]
                if element.integrated?
                    integrated = get(element.integrated_from.name)
                    return integrated.send(element.integrated_from_element) if integrated
                    return nil
                end
                if element_has_value?(name) || element_loaded?(name)
                    val = instance_variable_get(ivar)
                    val.set_parent(self, name) if val && element.model?
                    return val
                end

                #                Spider.logger.debug("Element not loaded #{name} (i'm #{self.class} #{self.object_id})")
                if autoload? && primary_keys_set?
                    if (autoload? == :save_mode)
                        mapper.load_element!(self, element)
                    else
                        mapper.load_element(self, element)
                    end
                    val = instance_variable_get(ivar)
                end
                if !val && element.model? && (element.multiple? || element.attributes[:extended_model])
                    val = instance_variable_set(ivar, instantiate_element(name))
                end
                if !val && element.attributes[:default]
                    if element.attributes[:default].is_a?(Proc)
                        val = element.attributes[:default].call(self)
                    else
                        val = element.attributes[:default]
                    end
                    val = element.model.new(val) if element.model? && !val.is_a?(BaseModel)
                end
                val.set_parent(self, name) if element.model? && val && val.respond_to?(:parent)
                return val
            end

            alias_method :"#{name}?", name if self.elements[name].type <= Spider::DataTypes::Bool

            #instance_variable_setter
            element_methods.send(:define_method, "#{name}=") do |val|
                element = self.class.elements[name]
                raise "Internal error! Element method #{name}= exists, but element not found" unless element
                return if element.attributes[:fixed]
                was_loaded = element_loaded?(element)
                #@_autoload = false unless element.primary_key?
                if (element.integrated?)
                    integrated_obj = get(element.integrated_from)
                    unless integrated_obj
                        integrated_obj = instantiate_element(element.integrated_from.name) 
                        set(element.integrated_from, integrated_obj)
                    end
                    #integrated_obj.autoload = false
                    begin
                        res = integrated_obj.send("#{element.integrated_from_element}=", val)
                    rescue IdentityMapperException
                        set(element.integrated_from, Spider::Model.get(integrated_obj))
                        get(element.integrated_from).merge!(integrated_obj)
                    end
                    if !element.primary_key? && integrated_obj.element_modified?(name)
                        @_modified_elements[name] = true
                    end
                    return res
                end
                if (val && element.model?)
                    if (element.multiple?)
                        unless (val.is_a?(QuerySet))
                            qs = instantiate_element(name)
                            if (val.is_a?(Enumerable))
                                val.each do |row|
                                    row = element.type.new(row) unless row.is_a?(BaseModel)
                                    qs << row
                                end
                            else
                                qs << val
                            end
                            val = qs
                        end
                    else
                        val = element.model.get(val) unless val.is_a?(BaseModel)
                    end
                end
                val = prepare_child(element.name, val)
                _check(name, val)
                notify_observers(name, val)
                @_has_values = true
                unless @_primary_keys_set
                    if self.class.elements[element.name].primary_key? && primary_keys_set?
                        @_primary_keys_set = true
                        if Spider::Model.identity_mapper
                            Spider::Model.identity_mapper.put(self, true, true)
                        else
                            Spider::Model.unit_of_work.add(self) if Spider::Model.unit_of_work
                        end
                    end
                end
                old_val = instance_variable_get(ivar)
                @_modified_elements[name] = true if !element.primary_key? && (!was_loaded || val != old_val)
                instance_variable_set(ivar, val)
                set_reverse(element, val) if element.model?
                if val && element.model? && !self.class.attributes[:no_type_check]
                    klass = val.is_a?(QuerySet) ? val.model : val.class
                    if val && !(klass <= element.type || klass <= element.model)
                        raise TypeError, "Object #{val} (#{klass}) is of the wrong type for element #{element.name} in #{self.class} (expected #{element.model})"
                    end
                end
                val
            end
        end
        
        # @private
        # Helper method that registers an element with the model
        # @param [Element] element
        # @return [void]
        def self.add_element(el)
            @elements ||= {}
            @elements[el.name] = el
            el.definer_model ||= self
            @elements_order ||= []
            if (el.attributes[:element_position])
                @elements_order.insert(el.attributes[:element_position], el.name)
            else
                @elements_order << el.name
            end            
            @primary_keys ||= []
            if el.attributes[:primary_key] && !@primary_keys.include?(el)
                @primary_keys << el
            end
        end
        
        
        # Removes a defined element
        # @param [Symbol|Element] element
        # @return nil 
        def self.remove_element(el)
            return unless @elements
            el = el.name if el.is_a?(Element)
            element = @elements[el]
            if self.attributes[:integrated_from_elements]
                self.attributes[:integrated_from_elements].each do |mod, iel|
                    i = mod.elements[el]
                    mod.remove_element(el) if i && i.integrated? && i.integrated_from.name == iel
                end
            end
            self.elements_array.select{ |e| e.integrated? && e.integrated_from.name == el}.each{ |e| remove_element(e) }
            self.const_get(:ElementMethods).send(:remove_method, :"#{el}") rescue NameError
            self.const_get(:ElementMethods).send(:remove_method, :"#{el}=") rescue NameError
            @extended_models.delete(element.type) if element && @extended_models && @extended_models[element.type] == el
            @elements.delete(el)
            @elements_order.delete(el)
            @primary_keys.delete_if{ |pk| pk.name == el}

            # if (@subclasses)
            #     @subclasses.each do |sub|
            #         sub.remove_element(el)
            #     end
            # end
        end
        
        # @private
        # Called when an element is defined
        # @return [void]
        def self.element_defined(el)
            if (@on_element_defined && @on_element_defined[el.name])
                @on_element_defined[el.name].each do |proc|
                    proc.call(el)
                end
            end
        end
        
        # Registers a block that will be called whenever an element is defined.
        # 
        # The block will be called with the created element as an argument.
        # @param [Symbol] element_name 
        # @param [Proc] proc A block to execute
        def self.on_element_defined(el_name, &proc)
            @on_element_defined ||= {}
            @on_element_defined[el_name] ||= []
            @on_element_defined[el_name] << proc
        end
            
        # Integrates an element: any call to the child object's elements will be passed to the child.
        # The element must not be multiple.
        # Example:
        #   class Address < BaseModel
        #     element :street, String
        #     element :area_code, String
        #   end
        #   class Person < BaseModel
        #     element :name, String
        #     element :address, Address
        #     integrate :address
        #   end
        #   p = Person.new(...)
        #   p.street == p.address.street
        # @param [Symbol] element_name
        # @param [Hash] params Params can be:
        #                      * :except     Excludes some elements of the integrated model
        #                      * :overwrite  Allows overwriting this model's elements with the integrated model's ones.
        #                      * :keep_pks   Integrate the model's primary keys as well
        #                      * :hidden     Set the :hidden attribute on integrated elements
        #                      * :mapping    An Hash of new names to assign to integrated elements
        # @return [void]
        def self.integrate(element_name, params={})
            params ||= {}
            elements[element_name].attributes[:integrated_model] = true
            model = elements[element_name].type
            self.attributes[:integrated_models] ||= {}
            self.attributes[:integrated_models][model] = element_name
            params[:except] ||= []
            model.each_element do |el|
                next if params[:except].include?(el.name)
                next if elements[el.name] unless params[:overwrite] # don't overwrite existing elements
                next if el.reverse == element_name && el.type == self
                integrate_element(element_name, el, params)
            end
            model.attributes[:integrated_from_elements] ||= []
            model.attributes[:integrated_from_elements] << [self, element_name]
        end
        
        # @private
        # Integrates a single element from a model.
        # See {BaseModel.integrate}
        # @param [Symbol] element_name
        # @param [Symbol] element_element The element inside the element's model to integrate
        # @param [Hash] params See {BaseModel.integrate}
        # @return [void]
        def self.integrate_element(element_name, element_element, params={})
            el = element_element
            el = self.elements[element_name].model.elements[el] if el.is_a?(Symbol)
            integrated_attributes = {}
            integrated_attributes[:primary_key] = false if params[:no_pks] # deprecated
            integrated_attributes[:hidden] = params[:hidden] unless (params[:hidden].nil?)

            integrated_attributes[:primary_key] = false unless (params[:keep_pks])
            # attributes.delete(:required)
            # attributes.delete(:integrate)
            # attributes.delete(:local_pk)
            integrated_attributes[:local_pk] = false
            integrated_attributes[:lazy] = element_name
            name = params[:mapping] && params[:mapping][el.name] ? params[:mapping][el.name] : el.name
            add_element(IntegratedElement.new(name, self, element_name, el.name, integrated_attributes))
            define_element_methods(name)
        end
        
        # Undoes an integration
        # See {BaseModel.integrate}
        # @param [Symbol|Element] element
        # @return [void]
        def self.remove_integrate(element_name)
            element = element_name.is_a?(Element) ? element_name : self.elements[element_name]
            model = element.model
            self.elements_array.select{ |el| el.attributes[:integrated_from] && el.attributes[:integrated_from].name == element.name }.each do |el|
                self.remove_element(el)
            end
            model.attributes[:integrated_from_elements].reject!{ |item| item[0] == self }
        end
        
        # Sets additional attributes on the element
        #
        # **Warning:** for attributes which are parsed by the BaseModel during element definition,
        # this will not have the desired effect; remove and redefine the element instead.
        # 
        # @param [Symbol] element_name
        # @param [Hash] attributes Attributes to set
        # @return [void]
        def self.element_attributes(element_name, attributes)
            elements[element_name].attributes = elements[element_name].attributes.merge(attributes)
            if attributes[:primary_key] && !@primary_keys.include?(elements[element_name])
                @primary_keys << elements[element_name]
            elsif !attributes[:primary_key]
                @primary_keys.delete(elements[element_name])
            end
        end
        
        # Defines a multiple element. Equivalent to calling
        #   element(name, type, :multiple => true, :association => :many, ...)
        # See also {BaseModel.element}.
        # @param [Symbol] name
        # @param [Class] type
        # @param [Hash] attributes
        # @param [Proc] proc
        # @return [Element]
        def self.many(name, type, attributes={}, &proc)
            attributes[:multiple] = true
            attributes[:association] ||= :many
            element(name, type, attributes, &proc)
        end
        
        # Defines an element with choice association. Shorthand for
        #   element(name, type, :association => :choice, ...)  
        # @param [Symbol] name
        # @param [Class] type
        # @param [Hash] attributes
        # @param [Proc] proc
        # @return [Element]   
        def self.choice(name, type, attributes={}, &proc)
            attributes[:association] = :choice
            element(name, type, attributes, &proc)
        end
        
        # Defines a multiple element with :multiple_choice association. Shorthand for
        #   many(name, type, :association => :multiple_choice, ...)
        def self.multiple_choice(name, type, attributes={}, &proc)
            attributes[:association] = :multiple_choice
            many(name, type, attributes, &proc)
        end
        
        # Defines an element which returns a query on another one.
        # @param [Symbol] name Name of the new element
        # @param [Sybmol] element_name Name of the element to run the query on
        # @param [Hash] attributes Attributes for the new elements. Must have a :condition attribute.
        def self.element_query(name, element_name, attributes={})
            orig_element = self.elements[element_name]
            set_el_query = lambda do
                orig_element = self.elements[element_name]
                attributes = attributes.merge(orig_element.attributes)
                attributes[:unmapped] = true
                attributes[:element_query] = element_name
                attributes[:association] = :element_query
                attributes[:lazy] = true
                attributes.delete(:add_reverse)
                attributes.delete(:add_multiple_reverse)
                if (orig_element.attributes[:condition])
                    cond = orig_element.attributes[:condition].clone
                    cond = cond.and(attributes[:condition]) if attributes[:condition]
                    attributes[:condition] = cond
                end
                element(name, orig_element.type, attributes)
            end
            if (orig_element)
                set_el_query.call
            else
                on_element_defined(element_name, &set_el_query)
            end
        end
        
        
        # @private
        # Creates an element with an {InlineModel} as type.
        # @param [Symbol] name Element name
        # @param [Hash] hash The hash to create the inline model from 
        # @param [Hash] attributes Attributes for the new element
        def self.create_inline_model(name, hash, attributes={})
            model = self.const_set(Spider::Inflector.camelize(name), Class.new(InlineModel))
            model.instance_eval do
                if attributes[:inline_model]
                    attributes[:inline_model].each do |el|
                        element(el[0], el[1], el[2] || {})
                    end
                else
                    hash.each do |key, val|
                        key = key.to_s if key.is_a?(Symbol)
                        element(:id, key.class, :primary_key => true)
                        if (val.class == Hash)
                            # TODO: allow passing of multiple values like {:element1 => 'el1', :element2 => 'el2'}
                        else
                            element(:desc, val.class, :desc => true)
                        end
                        break
                    end
                end
            end
            model.data = hash
            return model
        end
        
        # An array of other models this class points to.
        # @return [Array] An array of models which are referenced by this one's elements.
        def self.submodels
            elements.select{ |name, el| el.model? }.map{ |name, el| el.model }
        end
        
        
        # @return [void]
        def self.extend_model(model, params={}) #:nodoc:
            if (model == superclass) # first undo table per class inheritance
                @elements = {}
                @elements_order = []
                @extended_models.delete(model.superclass) if @extended_models
            end
            primary_keys.each{ |k| remove_element(k) } if (params[:replace_pks])
            model.primary_keys.each{ |k| remove_element(k) }
            integrated_name = params[:name]
            if (!integrated_name)
                integrated_name = (self.parent_module == model.parent_module) ? model.short_name : model.name
                integrated_name = Spider::Inflector.underscore(integrated_name).gsub('/', '_')
            end
            integrated_name = integrated_name.to_sym
            @extended_models ||= {}
            @extended_models[model] = integrated_name
            attributes = {}
            attributes[:hidden] = true unless params[:hide_integrated] == false
            attributes[:delete_cascade] = params[:delete_cascade]
            attributes[:extended_model] = true
            attributes[:embedded] = true unless params[:embedded] == false
            attributes[:add_reverse] = params[:reverse]
            integrated = element(integrated_name, model, attributes)
            integrate_options = {:keep_pks => true}.merge((params[:integrate_options] || {}))
            integrate(integrated_name, integrate_options)
            model.elements_array.select{ |el| el.attributes[:local_pk] }.each{ |el| remove_element(el.name) }

            unless (params[:no_local_pk] || !elements_array.select{ |el| el.attributes[:local_pk] }.empty?)
                # FIXME: check if :id is already defined
                pk_name = @elements[:id] ? :"id_#{self.short_name.downcase}" : :id
                element(pk_name, Fixnum, :autoincrement => true, :local_pk => true, :hidden => true)
            end
            model.polymorphic(self, :through => integrated_name)
        end
        
        # Externalizes the superclass elements making the superclass an external integrated element.
        # @param [Hash] params Parameters may be:
        #                       * :name               (symbol) name of the created element
        #                       * :delete_cascade     (bool) delete cascade the superclass instance. True by default.
        #                       * :no_local_pk        (bool) do not define an id for this class
        # @return [void]
        def self.class_table_inheritance(params={})
            self.extend_model(superclass, params)
        end
        
        # Makes the class use the superclass storage
        def self.inherit_storage
            self.attributes[:inherit_storage] = true
            (class << self; self; end).instance_eval do
                define_method(:storage) do
                    superclass.storage
                end
            end
        end
        
        # Sets a fixed condition.
        def self.condition(condition)
            self.attributes[:condition] = condition
        end
        
        #
        #--
        # TODO: document me
        def self.group(name, &proc) #:nodoc:
            proxy = Class.new(ProxyModel).proxy(name.to_s+'_', self)
            proxy.instance_eval(&proc)
            proxy.each_element do |el|
                element(name.to_s+'_'+el.name.to_s, el.type, el.attributes.clone)
            end
            define_method(name) do
                @proxies ||= {}
                return @proxies[name] ||= proxy.new
            end
            
        end
        
        # Add a subclass, allowing polymorphic queries on it.
        def self.polymorphic(model, options)
            through = options[:through] || Spider::Inflector.underscore(self.name).gsub('/', '_')
            through = through.to_sym
            @polymorphic_models ||= {}
            @polymorphic_models[model] = {:through => through}
        end

        # Sets or gets class attributes (a Hash).
        # If given a hash of attributes, will merge them with class attributes.
        # Model attributes are generally empty, and can be used by apps.
        def self.attributes(val=nil)
            @attributes ||= {}
            if (val)
                @attributes.merge!(val)
            end
            @attributes
        end
        
        # Sets a model attribute. See #self.attributes
        def self.attribute(name, value)
            @attributes ||= {}
            @attributes[name] = value
        end
        
        # Adds a sequence to the model.
        def self.sequence(name)
            @sequences ||= []
            @sequences << name
        end
        
        # Model sequences.
        def self.sequences
            @sequences ||= []
        end
        
        # Does nothing. This method is to keep note of elements created in other models.
        def self._added_elements(&proc)
        end
        
        def self.referenced_by_junctions
            @referenced_by_junctions ||= []
        end
        
        #####################################################
        #   Methods returning information about the model   #
        #####################################################
        
        # Underscored local name (without namespaces)
        def self.short_name
            return Inflector.underscore(self.name.match(/([^:]+)$/)[1])
        end
        
        # False for BaseModel (true for Spider::Model::Managed).
        def self.managed?
            return false
        end
        
        # Name
        def self.to_s
            self.name
        end
        
        # Sets the singolar and/or the plural label for the model
        # Returns the singlular label
        def self.label(sing=nil, plur=nil)
            @label = sing if sing
            @label_plural = plur if plur
            unless sing
                Spider::GetText.in_domain(self.app.short_name){
                    _(@label || self.name || '')
                }
            end
        end
        
        # Sets/retrieves the plural form for the label
        def self.label_plural(val=nil)
            @label_plural = val if (val)
            unless val
                Spider::GetText.in_domain(self.app.short_name){
                    _(@label_plural || self.name || '')
                }
            end
        end
        
        def self.label_
            @label
        end
        
        def self.label_plural_
            @label_plural
        end
        
        def self.auto_primary_keys?
            self.primary_keys.select{ |k| !k.autogenerated? }.empty?
        end
        
        def self.containing_module
            par = self.parent_module
            while par <= BaseModel
                par = par.parent_module
            end
            par
        end
        
        def self.get_element(el)
            el = el.name if el.is_a?(Element)
            el = el.to_sym
            raise "No element called #{el} in #{self}" unless @elements[el]
            @elements[el]
        end
        
        def self.junction?
            !!self.attributes[:sub_model]
        end
        
        def self.not_embeddable
            @embeddable = false
        end
        
        def self.embeddable?
            @embeddable.nil? ? true : @embeddable
        end
        
        def self.only_embedded
            @only_embedded = true
        end
        
        def self.only_embedded?
            @only_embedded
        end
        
        ########################################################
        #   Methods returning information about the elements   #
        ########################################################
        
        # An Hash of Elements, indexed by name.
        def self.elements
            @elements
        end

        # An array of non-integrated elements
        def self.own_elements
            elements_array.reject{ |el| el.integrated? }
        end
        
        # An array of the model's Elements.
        def self.elements_array
            @elements_order.map{ |key| @elements[key] }
        end

        # Yields each element in order.
        def self.each_element
            return unless @elements_order
            @elements_order.each do |name|
                yield elements[name]
            end
        end
        
        # Returns true if the model has given element name.
        def self.has_element?(name)
            return elements[name] ? true : false
        end
        
        # An array of elements with primary_key attribute set.
        def self.primary_keys
            @primary_keys
        end
        
        # Returns the model actually defining element_name; that could be the model
        # itself, a superclass, or an integrated model.
        def self.first_definer(element_name, type=nil)
            type ||= self.elements[element_name].type
            if @extended_models && @extended_models[self.superclass] && self.superclass.elements[element_name] && \
                    self.superclass.elements[element_name].type == type
                return self.superclass.first_definer(element_name, type)
            end
            if self.attributes[:integrated_models]
                self.attributes[:integrated_models].keys.each do |mod|
                    return mod.first_definer(element_name, type) if (mod.elements[element_name] && mod.elements[element_name].type == type)
                end
            end
            return self
        end
        
        # Returns true if the element with given name is associated with the passed
        # association.
        # This method should be used instead of querying the element's association directly,
        # since subclasses and mixins may extend this method to provide association equivalence.
        def self.element_association?(element_name, association)
            return true if elements[element_name].association = association
        end
        
        # An Hash of extended models => element name of the extended model element
        def self.extended_models
            @extended_models ||= {}
        end
        
        ##############################################################
        #   Storage, mapper and loading (Class methods)       #
        ##############################################################
        
        # The given module will be mixed in any mapper used by the class.
        def self.mapper_include(mod)
            @mapper_modules ||= []
            @mapper_modules << mod
        end
        
        def self.mapper_include_for(params, mod)
            params = [params] unless params.is_a?(Array)
            @mapper_modules_for ||= []
            @mapper_modules_for << [params, mod]
        end
        
        # The given proc will be mixed in the mapper used by this class
        # Note that the proc will be converted to a Module, so any overridden methods will still have 
        # access to the super method.
        def self.with_mapper(&proc)
            mod = Module.new
            mod.send(:include, Spider::Model::MapperIncludeModule)
            mod.module_eval(&proc)
            mapper_include(mod)
        end
                
        # Like #with_mapper, but will mixin the block only if the mapper matches params.
        # Possible params are:
        # - a String, matching the class' use_storage
        def self.with_mapper_for(*params, &proc)
            mod = Module.new
            mod.send(:include, Spider::Model::MapperIncludeModule)
            mod.module_eval(&proc)
            mapper_include_for(params, mod)
        end
        
        # Sets the url or the name of the storage to use
        def self.use_storage(name=nil)
            @use_storage = name if name
            @use_storage ||= self.attributes[:sub_model].use_storage if self.attributes[:sub_model]
            @use_storage ||= self.superclass.use_storage if self.superclass.respond_to?(:use_storage) && self.superclass.use_storage
            @use_storage
        end
        
        # Returns the current default storage for the class
        # The storage to use can be set with #use_storage
        def self.storage
            return @storage if @storage
            st = self.use_storage
            return st ? get_storage(st) : get_storage
        end

        def self.storage=(val)
            @storage = val
        end
        
        # Returns an instancethe storage corresponding to the storage_string if it is given, 
        # or of the default storage otherwise.
        # The storage string can be a storage url (see #Storage.get_storage), or a named storage
        # defined in configuration
        #--
        # Mixin!
        def self.get_storage(storage_string='default')
            storage_regexp = /([\w\d]+?):(.+)/
            orig_string = nil
            if (storage_string !~ storage_regexp)
                orig_string = storage_string
                storage_conf = Spider.conf.get('storages')[storage_string]
                storage_string = storage_conf['url'] if storage_conf
                if (!storage_string || storage_string !~ storage_regexp)
                    raise ModelException, "No storage '#{orig_string}' found"
                end
            end
            type, url = $1, $2
            storage = Storage.get_storage(type, url)
            storage.instance_name = orig_string
            storage.configure(storage_conf) if storage_conf
            return storage
        end
         
        # Returns an instance of the default mapper for the class. 
        def self.mapper
            @mapper ||= get_mapper(storage)
        end

        # Returns an instance of the mapper for the given storage
        def self.get_mapper(storage)
#            map_class = self.attributes[:inherit_storage] ? superclass : self
            mapper = storage.get_mapper(self)
            if (@mapper_modules)
                @mapper_modules.each{ |mod| mapper.extend(mod) }
            end
            if (@mapper_modules_for)
                @mapper_modules_for.each do |params, mod|
                    if (params.length == 1 && params[0].class == String)
                        mapper.extend(mod) if self.use_storage == params[0]
                    end
                end
            end
            return mapper
        end

        # Syncs the schema with the storage.
        def self.sync_schema(options={})
            options = ({
                :force => false,
                :drop_fields => false,
                :update_sequences => false,
                :no_foreign_key_constraints => true
            }).merge(options)
            Spider::Model.sync_schema(self, options[:force], options)
        end

        # Executes #self.where, and calls QuerySet#load on the result.
        # Returns nil if the result is empty, the QuerySet otherwise
        # See #self.where for parameter syntax
        def self.find(*params, &proc)
            qs = self.where(*params, &proc)
            return qs.empty? ? nil : qs
        end
        
        # Executes #self.where, returning the first result.
        # See #self.where for parameter syntax.
        def self.load(*params, &proc)
            qs = self.where(*params, &proc)
            qs.only_one
            return qs[0]
        end
        
        # Returns a queryset without conditions
        def self.all
            return self.where
        end
        
        # Returns a queryset with the objects that should be shown to the user. By default
        # returns self.all
        def self.list
            return self.all
        end
        
        # Constructs a Query based on params, and returns a QuerySet
        # Allowed parameters are:
        # * a Query object
        # * a Condition and an (optional) Request, or anything that can be parsed by Condition.new and Request.new
        # If a block is provided, it is passed to Condition.parse_block.
        # Examples:
        #   felines = Animals.where({:family => 'felines'})
        #   felines = Animals.where({:family => 'felines'}, [:name, :description])
        #   cool_animals = Animals.where{ (has_fangs == true) | (has_claws == true)}
        # See also Condition#parse_block
        def self.where(*params, &proc)
            if (params[0] && params[0].is_a?(Query))
                query = params[0]
                qs = QuerySet.new(self, query)
            elsif(proc)
                qs = QuerySet.new(self)
                qs.autoload = true
                qs.where(&proc)
            else
                condition = params[0].is_a?(Condition) ? params[0] : Condition.and(params[0])
                request = params[1].is_a?(Request) ? params[1] : Request.new(params[1])
                query = Query.new(condition, request)
                qs = QuerySet.new(self, query)
            end
            return qs
        end
        
        # Returns the condition for a "free" text query
        # Examples:
        #   condition = News.free_query_condition('animals')
        #   animal_news = News.where(condition)
        def self.free_query_condition(q)
            c = Condition.or
            self.elements_array.each do |el|
                if (el.type == String || el.type == Text)
                    c.set(el.name, 'ilike', '%'+q+'%')
                end
            end
            return c
        end
        
        # Returns the number of objects in storage
        def self.count(condition=nil)
            mapper.count(condition)
        end
        
        # Can be defined to provide functionality to this model's querysets.
        def self.extend_queryset(qs)
        end
        
        #################################################
        #   Instance methods                            #
        #################################################
        
        # The constructor may take:
        # * an Hash of values, that will be set on the new instance; or
        # * a BaseModel instance; its values will be set on the new instance; or
        # * a single value; it will be set on the first primary key.
        def initialize(values=nil)
            @_autoload = true
            @_has_values = false
            @loaded_elements = {}
            @_modified_elements = {}
            @value_observers = nil
            @all_values_observers = nil
            @_extra = {}
            @model = self.class
            @_primary_keys_set = false
            set_values(values) if values
            # if primary_keys_set?
            #     @_primary_keys_set = true
            #     if Spider::Model.identity_mapper
            #         Spider::Model.identity_mapper.put(self, true)
            #     else
            #         Spider::Model.unit_of_work.add(self) if Spider::Model.unit_of_work
            #     end
            # else
            #     #nil
            # end
                
            
        end
        
        # Returns an instance of the Model with #autoload set to false
        def self.static(values=nil)
            obj = self.new
            obj.autoload = false
            obj.set_values(values) if values
            return obj
        end
        
        def self.create(values)
            obj = self.static(values)
            obj.insert
            return obj
        end
        
        def self.load_or_create(values)
            self.load(values) || self.create(values)
        end
        
        def self.get(values, static=false)
            return static ? self.static(values) : self.new(values) unless Spider::Model.identity_mapper
            values = [values] unless values.is_a?(Hash) || values.is_a?(Array)
            if values.is_a?(Array)
                vals = {}
                self.primary_keys.each_with_index do |k, i|
                    vals[k.name] = values[i]
                end
                values = vals
            end
            curr = Spider::Model.identity_mapper.get(self, values)
            curr.autoload = false if static
            return curr if curr
            obj = static ? self.static(values) : self.new(values)
            Spider::Model.identity_mapper.put(obj)
            obj
        end

        def self.get_static(values)
            self.get(values, true)
        end
        
        def set_values(values)
            if (values.is_a? Hash)
                values.keys.select{ |k| 
                    k = k.name if k.is_a?(Element)
                    self.class.elements[k.to_sym] && self.class.elements[k.to_sym].primary_key? 
                }.each do |k|
                    set!(k, values[k])
                end
                values.each do |key, val|
                    set!(key, val)
                end
            elsif (values.is_a? BaseModel)
                values.each_val do |name, val|
                    set(name, val) if self.class.has_element?(name)
                end
            elsif (values.is_a? Array)
                self.class.primary_keys.each_index do |i|
                    set(self.class.primary_keys[i], values[i])
                end
             # Single unset key, single value
            elsif ((empty_keys = self.class.primary_keys.select{ |key| !element_has_value?(key) }).length == 1)
                set(empty_keys[0], values)
            else
                raise ArgumentError, "Don't know how to construct a #{self.class} from #{values.inspect}"
            end
        end
        
        # Returns the instance's IdentityMapper
        def identity_mapper
            return Spider::Model.identity_mapper if Spider::Model.identity_mapper
            @identity_mapper ||= IdentityMapper.new
        end
        
        # Sets the instance's IdentityMapper.
        def identity_mapper=(im)
            @identity_mapper = im
        end
        
        # Returns a new instance for given element name.
        def instantiate_element(name)
            element = self.class.elements[name]
            if element.model?
                if element.multiple?
                    val = QuerySet.static(element.model)
                    val.modified = true
                else
                    val = element.type.new
                    val.autoload = autoload?
                end
            end
            val = prepare_child(name, val)
            instance_variable_set("@#{name}", val)
            set_reverse(element, val) if element.model?
            val
        end
        
        # Prepares an object that is being set as a child.
        def prepare_child(name, obj)
            element = self.class.elements[name]
            if obj.nil?
                obj = QuerySet.static(element.model) if element.multiple?
                return obj 
            end
            if (element.model?)
                # convert between junction and real type if needed
                if element.attributes[:junction]
                    if obj.is_a?(QuerySet) 
                        obj.no_autoload do
                            if (element.attributes[:keep_junction] && obj.model == element.type)
                                qs = QuerySet.new(element.model)
                                obj.each{ |el_obj| 
                                    qs << {element.reverse => self, element.attributes[:junction_their_element] => el_obj}
                                }
                                obj = qs
                            elsif (!element.attributes[:keep_junction] && obj.model == element.model)
                                instance_variable_set("@#{element.name}_junction", obj)
                                qs = QuerySet.new(element.type, obj.map{ |el_obj| el_obj.get(element.attributes[:junction_their_element])})

                                obj = qs
                            end 
                        end
                    else
                        if (!element.attributes[:keep_junction] && obj.class == element.model)
                            obj = obj.get(element.attributes[:junction_their_element])
                        end
                    end
                end
                self.class.elements_array.select{ |el| el.attributes[:fixed] }.each do |el|
                    if el.integrated_from == element
                        obj.set(el.integrated_from_element, el.attributes[:fixed])
                    end
                end
                obj.identity_mapper = self.identity_mapper if obj.respond_to?(:identity_mapper)
                if (element.multiple? && element.attributes[:junction] && element.attributes[:keep_junction])
                    obj.append_element = element.attributes[:junction_their_element]
                end
                if (element.attributes[:set] && element.attributes[:set].is_a?(Hash))
                    element.attributes[:set].each{ |k, v| obj.set(k, v) }
                    obj.reset_modified_elements(*element.attributes[:set].keys)
                    # FIXME: is it always ok to not set the element as modified? But otherwise sub objects
                    # are always saved (and that's definitely no good)
                end
                if element.type == self.class.superclass && self.class.extended_models[element.type] && self.class.extended_models[element.type] == element.name
                    obj._subclass_object = self
                end
            else
                obj = prepare_value(element, obj)
            end
            return obj
        end
        
        # Returns all children that can be reached from the current path. 
        # Path is expressed as a dotted String.
        def all_children(path)
            children = []
            no_autoload do
                el = path.shift
                if self.class.elements[el] && element_has_value?(el) && children = get(el)
                    if path.length >= 1
                        children = children.all_children(path)
                    end
                end
            end
            return children
        end
        
        # Sets the object currently containing this one (BaseModel or QuerySet)
        def set_parent(obj, element)
            @_parent = obj
            @_parent_element = element
        end
        
        def set_reverse(element, obj)
            return unless element.model? && obj
            if element.has_single_reverse? && (!element.attributes[:junction] || element.attributes[:keep_junction])
                unless element.multiple?
                    val = obj.get_no_load(element.reverse)
                    return if val && val.object_id == self.object_id
                end
                obj.set(element.reverse, self)
            end
        end
        
        # Returns the object's embedder element, if any
        def embedder
            self.class.elements_array.select{ |el| el.attributes[:embedder] && self.element_has_value?(el) }[0]
        end
        
        
        #################################################
        #   Get and set                                 #
        #################################################
        
        # Returns an element.
        # The element may be a symbol, or a dotted path String.
        # Will call the associated getter.
        #   cat.get('favorite_food.name')
        def get(element)
            element = element.name if element.is_a?(Element)
            first, rest = element.to_s.split('.', 2)
            if (rest)
                sub_val = send(first)
                return nil unless sub_val
                return sub_val.get(rest)
            end
            return send(element)
        end
        
        # Returns an element without autoloading it.
        def get_no_load(element)
            res = nil
            no_autoload do
                res = get(element)
            end
            return res
        end

        # Sets an element.
        # The element can be a symbol, or a dotted path String.
        # Will call the associated setter.
        #   cat.set('favorite_food.name', 'Salmon')
        def set(element, value, options={})
            element = element.name if element.is_a?(Element)
            first, rest = element.to_s.split('.', 2)
            if (rest)
                first_val = send(first)
                unless first_val
                    if (options[:instantiate])
                        first_val = instantiate_element(first.to_sym)
                        set(first, first_val)
                    else
                        raise "Element #{first} is nil, can't set #{element}" 
                    end
                end
                return first_val.set(rest, value, options)
            end
            return send("#{element}=", value)
        end
        
        # Sets an element, instantiating intermediate objects if needed
        def set!(element, value, options={})
            options[:instantiate] = true
            set(element, value, options)
        end
        
        # Calls #get on element; whenever no getter responds, returns the extra data.
        # See #[]=
        def [](element)
            element = element.name if element.is_a?(Element)
            begin
                get(element)
            rescue NoMethodError
                return @_extra[element]
            end
        end
        
        # If element is a model's element, calls #set.
        # Otherwise, stores the value in an "extra" hash, where it will be accessible by #[]
        def []=(element, value)
            element = element.name if element.is_a?(Element)
            if (self.class.elements[element])
                set(element, value)
            else
                @_extra[element] = value
            end
        end
            
        # Sets each value of a Hash.
        def set_hash(hash)
            hash.each { |key, val| set(key, val) }
        end
        
        # Prepares a value going to be set on the object. Will convert the value to the
        # appropriate type.
        def self.prepare_value(element, value)
            element = self.class.elements[element] unless element.is_a?(Element)
            if element.type < Spider::DataType && element.type.force_wrap?
                value = element.type.from_value(value) unless value.is_a?(element.type)
                if value
                    element.type.take_attributes.each do |a|
                        if element.attributes[a].is_a?(Proc)
                            value.attributes[a] = value.instance_eval(&element.attributes[a])
                        else
                            value.attributes[a] = element.attributes[a]
                        end
                    end
                    value = value.prepare
                end
            elsif element.model?
                value.autoload(autoload?, true) if value && value.respond_to?(:autolad)
            else
                type = element.type
                type = mapper.base_type(type) if type < Spider::DataType && type.mapper_dependant?
                case type.name
                when 'Date', 'DateTime'
                    return nil if value.is_a?(String) && value.empty?
                    parsed = nil
                    if (value.is_a?(String))
                        begin
                            parsed = element.type.strptime(value, "%Y-%m-%dT%H:%M:%S") rescue parsed = nil
                            parsed ||= element.type.lparse(value, :short) rescue parsed = nil
                            parsed ||= element.type.parse(value)
                        rescue ArgumentError => exc
                            raise FormatError.new(element, value, _("'%s' is not a valid date"))
                        end
                        value = parsed
                    end
                when 'String'
                when 'Spider::DataTypes::Text'
                    value = value.to_s
                when 'Fixnum', 'Spider::DataTypes::PK'
                    value = value.to_i
                end
            end
            value
        end
        
        def prepare_value(element, value)
            self.class.prepare_value(element, value)
        end
        
        # Sets a value without calling the associated setter; used by the mapper.
        def set_loaded_value(element, value, mark_loaded=true)
            element_name = element.is_a?(Element) ? element.name : element
            element = self.class.elements[element_name]
            unless element.blank?
                if element.integrated?
                    integrated = get(element.integrated_from)
                    integrated.set_loaded_value(element.integrated_from_element, value) if integrated
                else
                    value = prepare_child(element.name, value)
                    current = instance_variable_get("@#{element_name}")
                    current.set_parent(nil, nil) if current && current.is_a?(BaseModel)
                    value.set_parent(self, element.name) if value.is_a?(BaseModel)
                    instance_variable_set("@#{element_name}", value)
                end
                value.loaded = true if (value.is_a?(QuerySet))
                element_loaded(element_name) if mark_loaded
                set_reverse(element, value) if element.model? && value
                @_modified_elements[element_name] = false
            end
        end
        
        # Records that the element has been loaded.
        def element_loaded(element_name)
            element_name = self.class.get_element(element_name).name
            @loaded_elements[element_name] = true
        end
        
        # Returns true if the element has been loaded by the mapper.
        def element_loaded?(element)
            element = self.class.get_element(element).name
            return @loaded_elements[element]
        end        

        # Apply element checks for given element name and value. (See also #element, :check attribute).
        # Checks may be defined by the DataType, or be given as an element attribute.
        # The check can be a Regexp, that will be checked against the value, or a Proc, which is expected to
        # return true if the check is succesful, and false otherwise.
        # Will raise a Model::FormatError when a check is not succesful.
        # If the :check attribute is an Hash, the Hash keys will be used as messages, which will be passed
        # to the FormatError.
        def _check(name, val)
            element = self.class.elements[name]
            element.type.check(val) if (element.type.respond_to?(:check))
            if (checks = element.attributes[:check])
                checks = {_("'%s' is not in the correct format") => checks} unless checks.is_a?(Hash)
                checks.each do |msg, check|
                    test = case check
                    when Regexp
                        val.blank? ? true : check.match(val.to_s)
                    when Proc
                        check.call(val)
                    end
                    raise FormatError.new(element, val, msg) unless test
                end
            end
        end
        
        # Converts the object to the instance of a subclass for which this model is polymorphic.
        def polymorphic_become(model)
            return self if self.is_a?(model)
            unless self.class.polymorphic_models && self.class.polymorphic_models[model]
                sup = model.superclass
                while sup < Spider::Model::BaseModel && !self.class.polymorphic_models[sup]
                    sup = sup.superclass
                end
                raise ModelException, "#{self.class} is not polymorphic for #{model}" unless self.class.polymorphic_models[sup]
                sup_poly = polymorphic_become(sup)
                return sup_poly.polymorphic_become(model)
            end
            el = self.class.polymorphic_models[model][:through]
            obj = model.new(el => self)
            obj = Spider::Model.identity_mapper.get(obj) if Spider::Model.identity_mapper
            obj.element_loaded(el)
            return obj
        end
        
        def become(model)
            return self if self.class == model
            obj = polymorphic_become(model) rescue ModelException
            return obj
        end
        
        # Converts the object to the instance of a subclass. This will instantiate the model
        # passed as an argument, and set each value of the current object on the new one.
        # No checks are made that this makes sense, so the method will fail if the "subclass" does
        # not contain all of the current model's elements.
        def subclass(model)
            obj = model.new
            self.class.elements_array.each do |el|
                obj.set(el, self.get(el)) if element_has_value?(el) && model.elements[el.name]
            end
            return obj
        end
        
        # Returns the current autoload status
        def autoload?
            @_autoload
        end
        
        # Enables or disables autoloading.
        # An autoloading object will try to load all missing elements on first access.
        # (see also Element#lazy_groups)
        def autoload=(val)
            autoload(val, false)
        end
        
        # Sets autoload mode
        # The first parameter the value of autoload to be set; it can be true, false or :save_mode (see #save_mode))
        # the second bool parameter specifies if the value should be propagated on all child objects.
        def autoload(a, traverse=true) #:nodoc:
            return if @_tmp_autoload_walk
            @_tmp_autoload_walk = true
            @_autoload = a
            if (traverse)
                self.class.elements_array.select{ |el| el.model? && \
                    (element_has_value?(el.name) || el.attributes[:extended_model])}.each do |el|
                    val = get(el)
                    val.autoload = a if val.respond_to?(:autoload=)
                end
            end
            @_tmp_autoload_walk = nil
        end
        
        # Disables autoload.
        # If a block is given, the current autoload setting will be restored after yielding.
        def no_autoload
            prev_autoload = autoload?
            self.autoload = false
            if block_given?
                yield
                self.autoload = prev_autoload
            end
            return prev_autoload
        end
        
        # Sets autoload to :save_mode; elements will be autoloaded only one by one, so that
        # any already set data will not be overwritten
        # If a block is given, the current autoload setting will be restored after yielding.
        def save_mode
            prev_autoload = autoload?
            self.autoload = :save_mode unless prev_autoload == false
            if (block_given?)
                yield
                self.autoload = prev_autoload
            end
            return prev_autoload
        end
            
        
        ##############################################################
        #   Methods for getting information about element values     #
        ##############################################################
        
        # Returns true if other is_a?(self.class), and has the same values for this class' primary keys.
        def ==(other)
            return false unless other
            return false unless other.is_a?(self.class)
            self.class.primary_keys.each do |k|
                return false unless get(k) == other.get(k)
            end
            return true
        end
        
        # Like ==, but other must be of the same class (no subclasses)
        def eql?(other)
            return false unless other.class == self.class
            return self == other
        end
        
        
        ##############################################################
        #   Iterators                                                #
        ##############################################################
        
        # Iterates over elements and yields name-value pairs
        def each # :yields: element_name, element_value
            self.class.elements.each do |name, el|
                yield name, get(name)
            end
        end

        # Iterates over non-nil elements, yielding name-value pairs
        def each_val # :yields: element_name, element_value
            self.class.elements.select{ |name, el| element_has_value?(name) }.each do |name, el|
                yield name, get(name)
            end
        end
        
        # Returns an array of current primary key values
        def primary_keys
            self.class.primary_keys.map{ |k|
                val = get(k)
                k.model? && val ? val.primary_keys : val
            }
        end
        
        # Returns an hash of primary keys names and values
        def primary_keys_hash
            h = {}
            self.class.primary_keys.each{ |k| h[k.name] = get(k) }
            h
        end
        
        # Returns a string with the primary keys joined by ','
        def keys_string
            self.class.keys_string(self.primary_keys)
        end
        
        
        def self.keys_string(keys)
            keys.join(',')
        end
        
        def self.split_keys_string(string)
            string.split(',')
        end

            
        
        # Returns true if the element instance variable is set
        #--
        # FIXME: should probably try to get away without this method
        # it is the only method that relies on the mapper
        def element_has_value?(element)
            element = self.class.get_element(element)
            if (element.integrated?)
                return false unless obj = instance_variable_get(:"@#{element.integrated_from.name}")
                return obj.element_has_value?(element.integrated_from_element)
            end
            if (element.attributes[:computed_from])
                element.attributes[:computed_from].each{ |el| return false unless element_has_value?(el) }
                return true
            end
            ivar = nil
            ivar = instance_variable_get(:"@#{element.name}") if instance_variable_defined?(:"@#{element.name}")
            return nil == ivar ? false : true 
            # FIXME: is this needed?
            # if (!mapper.mapped?(element)
            #     return send("#{element_name}?") if (respond_to?("#{element_name}?"))
            #     return get(element) == nil ? false : true if (!mapper.mapped?(element))
            # end
        end

        #METODO AGGIUNTO SOLO PER ATTRIBUTO :REQUIRED => true 
        def element_empty?(element)
            element = self.class.get_element(element)
            if (element.integrated?)
                return false unless obj = instance_variable_get(:"@#{element.integrated_from.name}")
                return obj.element_has_value?(element.integrated_from_element)
            end
            if (element.attributes[:computed_from])
                element.attributes[:computed_from].each{ |el| return false unless element_has_value?(el) }
                return true
            end
            ivar = nil
            ivar = instance_variable_get(:"@#{element.name}") if instance_variable_defined?(:"@#{element.name}")
            return ( "" == ivar ? true : false ) 
            # FIXME: is this needed?
            # if (!mapper.mapped?(element)
            #     return send("#{element_name}?") if (respond_to?("#{element_name}?"))
            #     return get(element) == nil ? false : true if (!mapper.mapped?(element))
            # end
        end

        # Returns true if the element value has been modified since instantiating or loading
        def element_modified?(element)
            element = self.class.get_element(element)
            set_mod = @_modified_elements[element.name]
            return set_mod if set_mod
            if element.integrated?
                return false unless integrated = get_no_load(element.integrated_from)
                return integrated.element_modified?(element.integrated_from_element)
            end
            if element_has_value?(element)
                val = get(element)
                # don't call modified? on QuerySets, since we don't need to query sub objects (this could lead to infinite loops)
                return val.modified if val.is_a?(QuerySet) 
                return val.modified? if val.respond_to?(:modified?)
            end
            return false
        end
        
        # Returns true if any of elements has been modified
        def elements_modified?(*elements)
            elements = elements[0] if elements[0].is_a?(Array)
            elements.each{ |el| return true if element_modified?(el) }
            return false
        end
        
        # Returns true if any element, or any child object, has been modified
        def modified?
            return true unless @_modified_elements.reject{ |key, val| !val }.empty?
            self.class.elements_array.select{ |el| 
                element_has_value?(el) && (el.type.is_a?(Spider::DataType) || el.multiple?)
            }.each do |el|
                obj = get(el)
                check = obj.is_a?(QuerySet) ? obj.modified : obj.modified?
                return true if check
            end
            return false
        end
        
        def in_storage?
            return false unless primary_keys_set?
            return self.class.load(primary_keys_hash)
        end
        
        # Given elements are set as modified
        def set_modified(request) #:nodoc:
            request = {request => true} unless request.is_a?(Hash)
            request.each do |key, val| # FIXME: go deep
                key = key.name if key.is_a?(Element)
                @_modified_elements[key] = true
                el = self.class.elements[key.to_sym]
                next unless el
                next if el.attributes[:unmapped]
                if el.integrated? && sub = self.get(el.integrated_from)
                    sub.set_modified(el.integrated_from_element)
                end
                
            end
        end
        
        # Resets modified elements
        def reset_modified_elements(*elements) #:nodoc:
            if (elements.length > 0)
                elements.each{ |el_name| @_modified_elements.delete(el_name) }
            else
                @_modified_elements = {}
            end
            elements = self.class.elements_array.map{ |el| el.name } if elements.empty?
            elements.each do |el_name|
                val = instance_variable_get("@#{el_name}")
                val.modified = false if val.is_a?(QuerySet)
            end

            nil
        end
        
        # Returns true if all primary keys have a value; false if some primary key
        # is not set or the model has no primary key
        def primary_keys_set?
            primary_keys = self.class.primary_keys
            return false unless primary_keys.length > 0
            primary_keys.each do |el|
                if (el.integrated?)
                    return false unless (int_obj = instance_variable_get(:"@#{el.integrated_from.name}"))
                    #return false unless int_obj.instance_variable_get(:"@#{el.integrated_from_element}")
                    return false unless int_obj.element_has_value?(el.integrated_from_element)
                else
                    return false unless self.instance_variable_get(:"@#{el.name}")
                end
            end
            return true
        end
        
        # Returns true if no element has a value
        def empty?
            return !@_has_values
        end
        
        # Sets all values of obj on the current object
        def merge!(obj, only=nil)
            return self if obj.object_id == self.object_id
            obj.class.elements_array.select{ |el| 
                (only || obj.element_has_value?(el)) && !el.integrated? && !el.attributes[:computed_from]
            }.each do |el|
                next if only && !only.key?(el.name)
                val = obj.element_has_value?(el.name) ? obj.get_no_load(el) : nil
                our_val = self.element_has_value?(el.name) ? self.get_no_load(el) : nil
                next if our_val == val
                if el.model? && only && only[el.name].is_a?(Hash) && our_val \
                    && val.is_a?(BaseModel) && our_val.is_a?(BaseModel)
                    val = our_val.merge!(val, only[el.name])                    
                else
                    Spider.logger.warn("Element #{el.name} overwritten in #{obj.inspect}") if our_val && our_val != val
                end
                set_loaded_value(el, val, false) # unless val.nil? && element.multiple?
            end
            self
        end
        
        def merge_hash(h)
            h.each do |k, v|
                self.set(k.to_sym, v)
            end
        end
        
        # Returns a deep copy of the object
        def clone
            obj = self.class.new
            obj.merge!(self)
            return obj
        end
        
        # Returns a new instance with the same primary keys
        def get_new
            obj = nil
            Spider::Model.no_identity_mapper do
                obj = self.class.new
                obj._no_identity_mapper = true
                self.class.primary_keys.each{ |k| obj.set(k, self.get(k)) }
            end
            return obj
        end
        
        # Returns a new static instance with the same primary keys
        def get_new_static
            obj = nil
            Spider::Model.no_identity_mapper do
                obj = self.class.static
                obj._no_identity_mapper = true
                self.class.primary_keys.each{ |k| obj.set(k, self.get(k)) }
            end
            return obj
        end
        
        # Returns a condition based on the current primary keys
        def keys_to_condition
            c = Condition.and
            self.class.primary_keys.each do |key|
                val = get(key)
                if (key.model?)
                    c[key.name] = val.keys_to_condition
                else
                    c[key.name] = val
                end
            end
            return c
        end
        
        
        #################################################
        #   Object observers methods                    #
        #################################################
        
        # The given block will be called whenever a value is modified.
        # The block will be passed three arguments: the object, the element name, and the previous value
        # Example:
        #   obj.observe_all_values do |instance, element_name, old_val|
        #     puts "#{element_name} for object #{instance} has changed from #{old_val} to #{instance.get(element_name) }"
        def observe_all_values(&proc)
            @all_values_observers ||= []
            @all_values_observers << proc
        end
        
        def observe_element(element_name, &proc)
            @value_observers ||= {}
            @value_observers[element_name] ||= []
            @value_observers[element_name] << proc
        end
        
        def self.observer_all_values(&proc)
            self.all_values_observers << proc
        end
        
        def self.observe_element(element_name, &proc)
            self.value_observers[element_name] ||= []
            @value_observers[element_name] << proc
        end
        
        def self.value_observers
            @value_observers ||= {}
        end
        
        def self.all_values_observers
            @all_values_observers ||= []
        end
        
        
        # Calls the observers for element_name
        def notify_observers(element_name, new_val) #:nodoc:
            if @value_observers && @value_observers[element_name]
                @value_observers[element_name].each{ |proc| proc.call(self, element_name, new_val) }
            end
            if @all_values_observers
                @all_values_observers.each{ |proc| proc.call(self, element_name, new_val) }
            end
            self.class.notify_observers(element_name, new_val, self)
        end
        
        # Calls the observers for element_name
        def self.notify_observers(element_name, new_val, obj=nil)
            if @value_observers && @value_observers[element_name]
                @value_observers[element_name].each{ |proc| proc.call(obj, element_name, new_val) }
            end
            if @all_values_observers
                @all_values_observers.each{ |proc| proc.call(obj, element_name, new_val) }
            end
        end
        
        
        
        ##############################################################
        #   Storage, mapper and schema loading (instance methods)    #
        ##############################################################
        
        # Returns the current @storage, or instantiates the default calling Spider::BaseModel.storage
        def storage
            return @storage || self.class.storage
        end
        
        # Instantiates the storage for the instance.
        # Accepts a string (url or named storage) which will be passed to Spider::BaseModel.get_storage
        # Example:
        #    obj.use_storage('my_named_db')
        #    obj.use_storage('db:oracle://username:password@XE')
        def use_storage(storage)
            @storage = self.class.get_storage(storage)
            @mapper = self.class.get_mapper(@storage)
        end
        
        # Returns the current mapper, or instantiates a new one (base on the current storage, if set)
        def mapper
            @storage ||= nil
            if (@storage)
                @mapper ||= self.class.get_mapper(@storage)
            else
                @mapper ||= self.class.mapper
            end
            return @mapper
        end
        
        # Sets the current mapper
        def mapper=(mapper)
            @mapper = mapper
        end
        
        ##############################################################
        #   Saving and loading from storage methods                  #
        ##############################################################
        
        # Saves the object to the storage
        # (see Mapper#save)
        def save
            saving(:save) do
                before_save
                save!
            end
            self
        end
                
        def save!
            mapper.save(self)
            after_save
            self
        end
        
        # Saves the object and all child objects to the storage 
        # (see Mapper#save_all)
        def save_all
            mapper.save_all(self)
            self
        end
        
        def insert
            saving(:insert) do
                before_save
                insert!
            end
            self
        end
        
        # Inserts the object in the storage
        # Note: if the object is already present in the storage and unique indexes are enforced,
        # this will raise an error.
        # (See Mapper#insert).
        def insert!
            mapper.insert(self)
            after_save
            self
        end
        
        # Updates the object in the storage
        # Note: the update will silently fail if the object is not present in the storage
        # (see Mapper#update).
        def update
            saving(:update) do
                before_save
                update!
            end
            self
        end
        
        def update!
            mapper.update(self)
            after_save
            self
        end
        
        def unit_of_work_available?
            Spider.current[:unit_of_work] && !Spider.current[:unit_of_work].running?
        end
        

        # Deletes the object from the storage
        # (see Mapper#delete).
        def delete
            saving(:delete) do
                before_delete
                delete!
            end
            nil
        end
        
        def delete!
            mapper.delete(self)
            after_delete
            nil
        end
        
        def before_delete
        end
        
        def before_save
        end
        
        def after_save
            reset_modified_elements
            self.autoload = @_saving[:prev_autoload] if @_saving
            @_saving = nil
        end
        
        def after_delete
        end
        
        def saving(mode, &proc)
            @_saving ||= { :prev_autoload => save_mode }
            if unit_of_work_available?
                Spider.current[:unit_of_work].add(self, mode)
            else
                yield
            end
        end

        def saving?
            !@_saving.nil?
        end
                
        # Loads the object from the storage
        # Acceptable arguments are:
        # * a Query object, or
        # * a Request object, or a Hash, which will be converted to a Request, or
        # * a list of elements to request
        # It will then construct a Condition with current primary keys, and call Mapper#load
        # Note that an error will be raised by the Mapper if not all primary keys are set.
        def load(*params)
            if (params[0].is_a? Query)
                query = params[0]
            else
                return false unless primary_keys_set?
                query = Query.new
                if (params[0].is_a?(Request))
                    query.request = params.shift
                elsif (params[0].is_a?(Hash))
                    query.request = Request.new(params.shift)
                end
                
                elements = params.length > 0 ? params : self.class.elements.keys
                return true unless elements.select{ |el| !element_loaded?(el) }.length > 0
                elements.each do |name|
                    query.request[name] = true
                end
                query.condition.conjunction = :and
                self.class.primary_keys.each do |key|
                    query.condition[key.name] = get(key.name)
                end
            end
            #clear_values()
            return mapper.load(self, query) 
        end
        
        # Sets all values to nil
        def clear_values()
            self.class.elements.each_key do |element_name|
                instance_variable_set(:"@#{element_name}", nil)
            end
        end
        
        def remove_association(element, object)
            mapper.delete_element_associations(self, element, object)
        end
        
        # Method that will be called by the mapper before a query. May be overridden to preprocess the query.
        # Must return the modified query. Note: to prepare conditions, use prepare_condition, since it will
        # be called on subconditions as well.
        def self.prepare_query(query)
            query
        end
        
        ##############################################################
        #   Method missing                                           #
        ##############################################################
        
        # Tries the method on integrated models
        def method_missing(method, *args) #:nodoc:
            # UNUSED
            # case method.to_s
            # when /load_by_(.+)/
            #     element = $1
            #     if !self.class.elements[element.to_sym].attributes[:primary_key]
            #         raise ModelException, "load_by_ called for element #{element} which is not a primary key"
            #     elsif self.class.primary_keys.length > 1
            #         raise ModelException, "can't call #{method} because #{element} is not the only primary key"
            #     end
            #     query = Query.new
            #     query.condition[element.to_sym] = args[0]
            #     load(query)
            # else
            if (self.class.attributes[:integrated_models])
                self.class.attributes[:integrated_models].each do |model, name|
                    obj = send(name)
                    if (obj.respond_to?(method))
                        return obj.send(method, *args)
                    end
                end
            end
            raise NoMethodError, "undefined method `#{method}' for #{self.class}"
            #super
            # end
        end
        
        def respond_to?(symbol, include_private=false)
            return true if super
            if (self.class.attributes[:integrated_models])
                self.class.attributes[:integrated_models].each do |model, name|
                    if (model.method_defined?(symbol))
                        return true
                    end
                end
            end
            return false
        end
        
        # Returns a descriptive string for the object.
        # By default this method returns the value of the first String element, if any; otherwise,
        # the string representation of the first element of any type.
        # Descendant classes may well provide a better representation.
        def to_s
            desc_elements = self.class.elements_array.select{ |el| el.attributes[:desc] }
            unless desc_elements.empty?
                return desc_elements.sort{ |a, b| 
                    ad = a.attributes[:desc]; bd = b.attributes[:desc]
                    if ad == true && bd == true
                        0
                    elsif bd == true
                        -1
                    elsif ad == true
                        1
                    else
                        ad <=> bd
                    end
                }.map{ |el| self.get(el).to_s }.join(' ')
            end
            self.class.each_element do |el|
                if ((el.type == String || el.type == Text) && !el.primary_key?)
                    v = get(el)
                    return v ? v.to_s : ''
                end
            end
            el = self.class.elements_array[0]
            if element_has_value?(el)
                v = get(el)
                return v  ? v.to_s : ''
            end
            return ''
        end
        
        # A compact representation of the object.
        # Note: inspect will not autoload the object.
        def inspect
            ic = Iconv.new('UTF-8//IGNORE', 'UTF-8') if RUBY_VERSION =~ /1.8/
            enc = Spider.conf.get('storages')['default']['encoding']
            enc ||= 'UTF-8'
            
            self.class.name+': {' +
            self.class.elements_array.select{ |el| (element_loaded?(el) || element_has_value?(el)) && !el.hidden? } \
                .map{ |el|
                    val = get(el.name).to_s
                    if RUBY_VERSION =~ /1.8/
                        val = ic.iconv(val + ' ')[0..-2] if val
                    else
                        begin
                            val = ((val+' ').encode('UTF-8', enc, :invalid => :replace, :undef => :replace))[0..-2] if val
                        rescue EncodingError  
                            val = ''  
                        end 
                    end
                 ":#{el.name} => #{val}"}.join(',') + '}'
        end
        
        # Returns a JSON representation of the object.
        #
        # The tree will be traversed outputting all encountered objects; when an already seen object
        # is met, the primary keys will be output (as a single value if one, as an array if many) and traversing
        # will stop.
        #
        # For more fine-grained control of the output, it is better to use the #cut method and call to_json on it.
        def to_json(state=nil, &proc)
            require 'json'
            ic = Iconv.new('UTF-8//IGNORE', 'UTF-8') if RUBY_VERSION =~ /1.8/
            if (@tmp_json_seen && !block_given?)
                pks = self.class.primary_keys.map{ |k| get(k).to_json }
                pks = pks[0] if pks.length == 1
                return pks.to_json
            end
            @tmp_json_seen = true
            json = ""
            #Spider::Model.with_identity_mapper do |im|
            self.class.elements_array.select{ |el| el.attributes[:integrated_model] }.each do |el|
                (int = get(el)) && int.instance_variable_set("@tmp_json_seen", true)
            end
            if (block_given?)
                select_elements = Proc.new{ true }
            else
                select_elements = Proc.new{ |name, el|
                    !el.hidden?
                    #  &&
                    # #!el.attributes[:integrated_model]  && 
                    # (element_has_value?(el) || (el.integrated? && element_has_value?(el.integrated_from)))
                }
            end


            json = "{" +
            self.class.elements.select(&select_elements).map{ |name, el|
                if (block_given?)
                    val = yield(self, el)
                    val ? "#{name.to_json}: #{val.to_json}" : nil
                else
                    val = get(name)
                    enc = Spider.conf.get('storages')['default']['encoding']
                    enc ||= 'UTF-8'
                    if (el.type == String || el.type == Text)
                        if RUBY_VERSION =~ /1.8/
                            val = ic.iconv(val + ' ')[0..-2] if val
                        elsif val.is_a?(String) && val.encoding == "ASCII-8BIT" 
                                begin
                                    val = ((val+' ').force_encoding("UTF-8").encode('UTF-8', :invalid => :replace, :undef => :replace))[0..-2] if val
                                rescue
                                    Spider.logger.error("Errore di encoding relativamente al seguente valore inserito in json #{val}")
                                ensure
                                    val ||= ''
                                end
                        elsif val.is_a?(String)
                            begin
                                val = ((val+' ').encode('UTF-8', enc))[0..-2] if val
                            rescue EncodingError 
                                val = ((val+' ').encode('UTF-8', 'UTF-8', :invalid => :replace, :undef => :replace))[0..-2] if val
                            ensure
                                val ||= ''
                            end
                        end
                    end
                    val = val.to_json
                    "#{name.to_json}: #{val}"
                end
                }.select{ |pair| pair}.join(',') + "}"
                @tmp_json_seen = false
                self.class.elements_array.select{ |el| el.attributes[:integrated_model] }.each do |el|
                    (int = get(el)) && int.instance_variable_set("@tmp_json_seen", false)
                end
                #end
                return json
            end
        
        # Returns a part of the object tree, converted to Hashes, Arrays and Strings.
        # Arguments can be:
        # * a String, followed by a list of elements; the String will be sprintf'd with element values
        # or
        # * a depth Fixnum; depth 0 means obj.to_s will be returned, depth 1 will return an hash containing the
        #   object's element values converted to string, and so on
        # or
        # * a Hash, whith element names as keys, and depths, or Hashes, or Procs as values; each element
        #   will be traversed up to the depth given, or recursively according to the has; or, if a Proc is given,
        #   it will be called with the current object and element name as arguments
        # or
        # * a list of elements; this is equivalent to passing a hash of the elements with depth 0.
        #
        # Examples:
        #   obj.inspect
        #     => Zoo::Animal: {:name => Llama, :family => Camelidae, :friends => Sheep, Camel}
        #   obj.cut(0) 
        #     => 'Llama'
        #   obj.cut(:name, :friends) 
        #     => {:name => 'Llama', :friends => 'Sheep, Camel'}
        #   obj.cut(:name => 0, :friends => 1)
        #     => {:name => 'Llama', :friends => [
        #           {:name => 'Sheep', :family => 'Bovidae', :friends => 'Llama'},
        #           {:name => 'Camel', :family => 'Camelidae', :friens => 'Dromedary, LLama'}
        #         ]}
        #   obj.cut(:name => 0, :friends => {:name => 0})
        #     => {:name => 'Llama', :friends => [{:name => 'Sheep'}, {:name => 'Camel'}]}
        #   objs.cut(:name => 0, :friends => lambda{ |instance, element| 
        #      instance.get(element).name.upcase
        #   })
        #     => {:name => 'Llama', :friends => ['SHEEP', 'CAMEL']}
        #   obj.cut("Hi, i'm a %s and my friends are %s", :name, :friends)
        #     => "Hi, i'm a Llama and my friends are Sheep, Camel"
        def cut(*params, &proc)
            h = {}
            if (params[0].is_a?(String))
                return sprintf(params[0], *params[1..-1].map{ |el| get(el) })
            elsif (params[0].is_a?(Fixnum))
                p = params.shift
                if (p < 1)
                    if (block_given?)
                        return proc.call(self)
                    else
                        return self.to_s
                    end
                end
                lev = p
                where = {}
                self.class.elements_array.each { |el| where[el.name] = lev-1}
            end
            if (params[0].is_a?(Hash))
                where ||= {}
                params[0].each{ |k, v| where[k.to_sym] = v}
            else
                where ||= {}
                params.each{ |p| where[p] = 0 if p.is_a?(Symbol)}
            end
            Spider::Model.with_identity_mapper do |im|
                where.keys.each do |name|
                    next unless where[name]
                    if (where[name].is_a?(Proc))
                        val = where[name].call(self, name)
                    else
                        el = self.class.elements[name]
                        if el
                            val = get(el)
                            val = val.cut(where[name], &proc) if el.model? && val
                        else
                            raise ModelException, "Element #{name} does not exist" unless self.respond_to?(name)
                            val = self.send(name)
                            val = val.cut(where[name], &proc) if val.is_a?(BaseModel)
                        end
                    end
                    h[name] = val
                end
            end
            return h
        end
        
        # Returns a element_name => value Hash
        def to_hash()
            h = {}
            self.class.elements.select{ |name, el| element_loaded? el }.each do |name, el|
                h[name] = get(name)
            end
            return h
        end
        
        # Returns a yaml representation of the object. Will try to autoload all elements, unless autoload is false;
        # foreign keys will be expressed as an array if multiple, as a single primary key value otherwise
        def to_yaml(params={})
            require 'yaml'
            return YAML::dump(to_yaml_h(params))
        end
        
        def to_yaml_h(params={})
            h = {}
            def obj_pks(obj, klass)
                unless obj
                    return klass.primary_keys.length > 1 ? [] : nil
                end
                pks = obj.primary_keys
                return pks[0] if pks.length == 1
                return pks
            end 

            self.class.elements_array.each do |el|
                next if params[:except] && params[:except].include?(el.name)
                if (el.model?)
                    obj = get(el)
                    if !obj
                       h[el.name] = nil 
                    elsif (el.multiple?)
                        h[el.name] = obj.map{ |o| obj_pks(o, el.model) }
                    else
                        h[el.name] = obj_pks(obj, el.model)
                    end
                else
                    h[el.name] = get(el)
                end
            end
            h
        end
        
        def self.from_yaml(yaml)
            h = YAML::load(yaml)
            obj = self.static
            h.each do |key, value|
                el = elements[key.to_sym]
                if (el.multiple?)
                    el_obj = el.model.static
                    el.model.primary_keys.each do |pk|
                        el_obj.set(pk, value.unshift)
                    end
                    obj.set(el, el_obj)
                else
                    obj.set(el, value)
                end
            end
            return obj
        end
        
        def dump_to_hash
            h = {}
            def obj_pks(obj, klass)
                unless obj
                    return klass.primary_keys.length > 1 ? [] : nil
                end
                pks = obj.primary_keys
                return pks[0] if pks.length == 1
                return pks
            end 
            ic = Iconv.new('UTF-8//IGNORE', 'UTF-8') if RUBY_VERSION =~ /1.8/
            self.class.elements_array.each do |el|
                next unless mapper.have_references?(el) || (el.junction? && el.model.attributes[:sub_model] == self.class)
                if (el.model?)
                    obj = get(el)
                    if !obj
                       h[el.name] = nil 
                    elsif (el.multiple?)
                        h[el.name] = obj.map{ |o| obj_pks(o, el.model) }
                    else
                        h[el.name] = obj_pks(obj, el.model)
                    end
                else
                    val = get(el)
                    if val
                        case val.class.name.to_sym
                        when :Date, :DateTime, :Time
                            val = val.strftime
                        when :String
                            if RUBY_VERSION =~ /1.8/
                                val = ic.iconv(val) if val
                            else
                                val = val = val.force_encoding(Encoding::UTF_8).encode(Encoding::UTF_8) if val && val.encoding == Encoding::ASCII_8BIT
                            end
                        end
                    end
                    h[el.name] = val
                end
            end
            h
        end
        
        def self.from_hash_dump(h, options={})
            obj = self.static
            obj._check_if_saved = true if options[:check_if_saved]
            h.each do |key, val|
                el = self.elements[key.to_sym]
                next unless el
                if el.multiple? && val
                    qs = obj.get(el)
                    val.each do |v|
                        v = el.model.from_hash_dump(v, options) if v.is_a?(Hash)
                        qs << v
                    end
                else
                    val = el.model.from_hash_dump(val, options) if val.is_a?(Hash)
	                case el.type.name.to_sym
                    when :Date, :DateTime
                        val =  el.type.parse(val) unless val.blank?
                    end
					begin
                        obj.set(el, val)
                    rescue # FIXME: should be and option
                    end
                end
            end
            obj
        end
        
        def dump_to_all_data_hash(options={}, h={}, seen={})
            Spider::Model.with_identity_mapper do |im|
                clname = self.class.name.to_sym
                seen[clname] ||= {}
                return if seen[clname][self.primary_keys]
                seen[clname][self.primary_keys] = true
                h[clname] ||= []
                h[clname] << self.dump_to_hash
                self.class.elements_array.each do |el|
                    next unless el.model?
                    next if el.model < Spider::Model::InlineModel
                    next if options[:models] && !options[:models].include?(el.type)
                    next if options[:except_models] && options[:except_models].include?(el.type)
                    el_clname == el.type.name.to_sym
                    next if options[:elements] && (options[:elements][el_clname] && !options[:elements][el_clname].include?(el.name))
                    next if options[:except_elements] && (options[:except_elements][el_clname] && options[:except_elements][el_clname].include?(el.name))
                    val = self.get(el)
                    next unless val
                    val = [val] unless val.is_a?(Enumerable)
                    val.each do |v|
                        v.dump_to_all_data_hash(options, h, seen)
                    end
                end
            end
            h
        end
        
        def self.in_transaction
            self.storage.in_transaction
            yield
            self.storage.commit_or_continue
        end
        
        def self.dump_element(el)
            remove_elements = []
            method = case el.attributes[:association]
            when :many
                :many
            when :choice
                :choice
            when :multiple_choice
                :multiple_choice
            when :tree
                :tree
            else
                :element
            end
            type = el.type
            attributes = el.attributes.clone
            if (method == :many || method == :multiple_choice)
                attributes.delete(:multiple)
            end
            attributes.delete(:association) if method != :element
            if (attributes[:association_type])
                attributes[:through] = attributes[:association_type] unless attributes[:anonymous_model]
                attributes.delete(:association_type)
            end
            attributes.delete(:lazy) if attributes[:lazy] == :default
            if (method == :tree)
                delete_attrs = [:queryset_module, :multiple]
                delete_attrs.each{ |a| attributes.delete(a) }
                remove_elements += [attributes[:reverse], attributes[:tree_left], attributes[:tree_right], attributes[:tree_depth]]
                type = nil
            end
            return {
                :name => el.name,
                :type => type,
                :attributes => attributes,
                :method => method,
                :remove_elements => remove_elements
            }
        end
        
        def self.prepare_to_code
            modules = self.name.split('::')[0..-2]
            included = (self.included_modules - Spider::Model::BaseModel.included_modules).select do |m|
                m.name !~ /^#{Regexp.quote(self.name)}/
            end
            local_name = self.name.split('::')[-1]
            superklass = self.superclass.name
            elements = []
            remove_elements = []
            self.elements_array.each do |el|
                next if el.integrated?
                next if (el.reverse && el.model.elements[el.reverse] && \
                    (el.model.elements[el.reverse].attributes[:add_reverse] || \
                    el.model.elements[el.reverse].attributes[:add_multiple_reverse]))
                el_hash = dump_element(el)
                return nil unless el_hash
                elements << el_hash
                remove_elements += el_hash[:remove_elements]
            end
            elements.reject!{ |el| remove_elements.include?(el[:name]) }
            return {
                :modules => modules,
                :included => included,
                :attributes => self.attributes,
                :elements => elements,
                :local_name => local_name,
                :superclass => superklass,
                :use_storage => @use_storage,
                :additional_code => []
            }
        end
        
        def self.to_code(options={})
            c = prepare_to_code
            str = ""
            indent = 0
            append = lambda do |val|
                str += " "*indent
                str += val
                str
            end
            str += c[:modules].map{ |m| "module #{m}" }.join('; ') + "\n"
            str += "\n"
            indent = 4
            append.call "class #{c[:local_name]} < #{c[:superclass]}\n"
            indent += 4
            c[:included].each do |i|
                append.call "include #{i.name}\n"
            end
            c[:attributes].each do |k, v|
                append.call "attribute :#{k}, #{v.inspect}"
            end
            str += "\n"
            c[:elements].each do |el|
                append.call("#{el[:method].to_s} #{el[:name].inspect}")
                str += ", #{el[:type]}" if el[:type]
                str += ", #{el[:attributes].inspect[1..-2]}\n" if el[:attributes] && !el[:attributes].empty?
            end
            str += "\n"
            append.call "use_storage '#{c[:use_storage]}'\n" if c[:use_storage]
            c[:additional_code].each do |block|
                block.each_line do |line|
                    append.call line
                end
                str += "\n"
            end
            indent -= 4
            append.call("end\n")
            str += c[:modules].map{ "end" }.join(';')
            return str
        end
        
    end
    
end; end
