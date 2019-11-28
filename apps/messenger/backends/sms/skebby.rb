require 'apps/messenger/lib/sms_backend'
require 'apps/messenger/lib/backends/skebby'
require 'net/http'
require 'uri'
require 'cgi'


module Spider; module Messenger; module Backends; module SMS

    module Skebby
        include Messenger::SMSBackend


        def self.send_message(msg)
            Spider.logger.debug("**Sending SMS with skebby**")
            username = Spider.conf.get('messenger.skebby.username')
            password = Spider.conf.get('messenger.skebby.password')
            from = Spider.conf.get('messenger.skebby.from')    
            to = []
            to << msg.to.gsub("+","");
            text = msg.text
            gw = Spider::Messenger::Skebby::SkebbyGatewaySendSMS.new(username, password)
 
            #controllo il credito
            credito_presente = gw.getCredit()
            if credito_presente

                #Invio SMS Basic
                #result = gw.sendSMS('send_sms_basic', 'Hi Mike, how are you? By John', recipients )
                 
                #Invio SMS Classic con mittente personalizzato di tipo numerico
                #result = gw.sendSMS('send_sms_classic', 'Hi Mike, how are you', recipients, { :senderNumber => '393471234567' } )
                 
                #Invio SMS Classic con notifica(report) con mittente personalizzato di tipo alfanumerico - Invio SMS Classic Plus
                #result = gw.sendSMS('send_sms_classic_report', 'Hi Mike, how are you', recipients, { :senderString => 'Jhon' } )
                 
                #Invio SMS Classic con notifica(report) con mittente personalizzato di tipo numerico - Invio SMS Classic Plus
                #result = gw.sendSMS('send_sms_classic_report', 'Hi Mike, how are you', recipients, { :senderNumber => '393471234567' } )

                #Invio SMS Classic con mittente personalizzato di tipo alfanumerico
                result = gw.sendSMS('send_sms_classic_report', text, to, { :senderString => from, :charset => 'UTF-8' } )
                if result
                    gw.printResponse
                else
                    raise "Errore nell'invio degli sms."
                end  
            else
                raise "Il credito e insufficiente per mandare sms."
            end
                         
            
             
                
        end


    end



end; end; end; end    