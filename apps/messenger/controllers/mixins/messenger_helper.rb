require 'erb'
require 'mail'

Spider.register_resource_type(:email, :extensions => ['erb'], :path => 'templates/email')

module Spider; module Messenger
    
    module MessengerHelper
        
        # Compiles an e-mail from given template and scene, and sends it using
        # #Messenger::email
        # template is the template name (found in templates/email), without the extension
        # will use template.html.erb and template.txt.erb if they exist, template.erb otherwise.
        # attachments must be an array, which items can be strings (the path to the file)
        # or Hashes:
        # {:filename => 'filename.png', :content => File.read('/path/to/file.jpg'),
        #   :mime_type => 'mime/type'}
        # Attachments will be passed to the Mail gem (https://github.com/mikel/mail), so any syntax allowed by Mail
        # can be used
        def send_email(template, scene, from, to, headers={}, attachments=[], params={})
            klass = self.class if self.class.respond_to?(:find_resouce_path)
            klass ||= self.class.app if self.class.respond_to?(:app)
            klass ||= Spider.home
            msg = Spider::Messenger::MessengerHelper.send_email(klass, template, scene, from, to, headers, attachments, params)
            #tolto per invio di 3 mail in copia
            #sent_email(msg.ticket)
            msg
        end

        def send_sms(to, text, params=nil)
            params = {} if params.blank?
            to = "+39"+to if (!to.include?("+") && (to.length == 10 || to.length == 9) )
            if (to.length == 13 || to.length == 12)
                msg = Spider::Messenger.sms(to, text, params)
                #tolto per invio di 3 sms quando si inviano sms per rilevazione presenze 
                #sent_sms(msg.ticket)
                return msg
            else
                Spider.logger.error "Number #{to} not valid"
                return false
            end
            
        end
        
        def self.send_sms(to, text, params=nil)
            params = {} if params.blank?
            to = "+39"+to if (!to.include?("+") && (to.length == 10 || to.length == 9) )
            if (to.length == 13 || to.length == 12)
                msg = Spider::Messenger.sms(to, text, params)
                return msg
            else
                Spider.logger.error "Number #{to} not valid"
                return false
            end
        end



        def self.send_email(klass, template, scene, from, to, headers={}, attachments=[], params={})
            path_txt = klass.find_resource_path(:email, template+'.txt')
            path_txt = nil unless path_txt && File.exist?(path_txt)
            path_html = klass.find_resource_path(:email, template+'.html')
            path_html = nil unless path_html && File.exist?(path_html)

            #converte l'intera scene con ricorsione in utf-8 per evitare problemi in invio mail             
            scene.convert_object

            scene_binding = scene.instance_eval{ binding }
            if (path_txt || path_html)
                text = ERB.new( IO.read(path_txt) ).result(scene_binding) if path_txt
                html = ERB.new( IO.read(path_html) ).result(scene_binding) if path_html
            else
                path = klass.find_resource_path(:email, template)
                text = ERB.new( IO.read(path) ).result(scene_binding)
            end

            mail = Mail.new
            mail[:to] = to.convert_object 
            mail[:from] = from.convert_object 
            mail.charset = "UTF-8"
            headers.each do |key, value|
                mail[key] = value.convert_object 
            end

            # if html
            #     mail.html_part do
            #         content_type 'text/html; charset=UTF-8'
            #         body html
            #     end 
            # end  
            # if attachments && !attachments.empty?
            #     mail.text_part do
            #         body text
            #     end       
            # else
            #     mail.body = text
            # end
            #ritornato al vecchio metodo con piu controlli per problema con invio comunicazioni con immagini 5/2/2015

            if html || text
                mail.text_part do
                    body text
                end unless text.blank?
                mail.html_part do
                    content_type 'text/html; charset=UTF-8'
                    body html
                end unless html.blank?
            else
                mail.body = text
            end

            if attachments && !attachments.empty?
                attachments.each do |att|
                    if att.is_a?(Hash)
                        #filename = att.delete(:filename)
                        filename = att[:filename].dup
                        mime_type = att[:mime_type].dup
                        content = att[:content].dup
                        mail.attachments[filename] = { :mime_type => mime_type, :content => content }
                    else
                        mail.add_file(att)
                    end
                end
            end
            mail_headers, mail_body = mail.to_s.split("\r\n\r\n", 2)
            mail_headers += "\r\n"
            Messenger.email(from, to, mail_headers, mail_body, params)
        end
        
        def sent_email(ticket)
            sent_message(ticket, :email)
        end

        def sent_sms(ticket)
            sent_message(ticket, :sms)
        end

        def sent_message(ticket, type)
            return unless ticket
            type = type.to_sym
            @messenger_sent = Spider::Request.current[:messenger_sent]
            @messenger_sent ||= {}
            @messenger_sent[type] ||= []
            @messenger_sent[type] << ticket
            Spider::Request.current[:messenger_sent] = @messenger_sent
        end
        
        def after(action='', *params)
            @messenger_sent = Spider::Request.current[:messenger_sent]
            return super unless Spider.conf.get('messenger.send_immediate') && @messenger_sent
            @messenger_sent.each do |type, msgs|
                Spider::Messenger.process_queue(type, msgs)
            end
        end
        
    end
    
end; end
