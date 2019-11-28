class Module #:nodoc:

    # This is here just to be able to call this method on all constants
    def subclass_of?(klass)
        return false
    end
    
    def parent_module(n=1)
        part = self.to_s.reverse.split('::', n+1)[n]
        return nil if part.blank?
        return const_get_full(part.reverse)
    end
    
    def last_name
        self.to_s.split('::')[-1].to_sym
    end
    
    def const_set_full(name, val)
        mod = self
        parts = name.to_s.split('::')
        parts[0..-2].each do |part|
            unless mod.const_defined?(part.to_sym)
                mod.const_set(part.to_sym, Module.new)
            end
            mod = mod.const_get(part.to_sym)
        end
        mod.const_set(parts[-1].to_sym, val)
    end

    # const_defined? in Ruby 1.9 behaves differently in terms
    # of which class hierarchy it polls for nested namespaces
    #
    # See http://redmine.ruby-lang.org/issues/show/1915
    def constant_defined?(const)
      if ::RUBY_VERSION =~ /1.9/
        const_defined?(const, false)
      else
        const_defined?(const)
      end
    end
    
end