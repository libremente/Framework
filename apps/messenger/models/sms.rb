require 'apps/messenger/models/message'

module Spider; module Messenger
    
    class SMS < Message
        class_table_inheritance :add_polymorphic => true
        element :sender_name, String, :label => "Nome Ente"
        element :to, String, :label => _("To")
        element :text, Text, :label => _("Text")
        
        queue :sms
        
                
    end
    
end; end