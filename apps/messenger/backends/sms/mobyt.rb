require "apps/messenger/lib/sms_backend"
require "apps/messenger/lib/backends/mobyt"


module Spider; module Messenger; module Backends; module SMS

    module Mobyt
        include Messenger::SMSBackend

        def self.send_message(msg)
            #controllo il credito
            credito_presente = Spider::Messenger::Mobyt.getCredit
            if credito_presente

                Spider.logger.debug("**Sending SMS with mobyt**")
                username = Spider.conf.get('messenger.mobyt.username')
                password = Spider.conf.get('messenger.mobyt.password')
                from = Spider.conf.get('messenger.mobyt.from')    
                to = msg.to
                text = msg.text
                #uri = URI('http://smsweb.mobyt.it/sms-gw/sendsmart') vecchia

                uri = URI('http://app.mobyt.it/Mobyt/SENDSMS')
                
                testi = Hash.new
                #se mando messaggio lungo spezzo in più messaggi
                if text.size > 160
                    percorso_contatore = File.join(Spider.paths[:var], "contatore_mobyt")
                    sequence_index = ""
                    File.open(percorso_contatore, File::RDWR|File::CREAT) do |f|
                        f.flock(File::LOCK_EX)
                        sequence_index = f.read.to_i + 1
                        f.rewind
                        sequence_index = sequence_index % 99
                        f.write("#{sequence_index}")                        
                        f.flush
                        f.truncate(f.pos)
                    end
                    tot_response = true
                    operation="MULTI"
                    cnt = 0
                    index = 1
                    mes = ""
                    (text + " ").scan(/.{1,153}\s/).map{ |s|
                        testi[index] = s
                        index += 1 
                    }
                    tot_testi = testi.size
                    #tolgo lo spazio che era stato aggiunto al testo nell'ultimo messaggio
                    testi[tot_testi] = testi[tot_testi].strip
                    #invio sms con testi in hash testi
                    testi.each{ |key,testo|
                        sequence_index = sequence_index.to_s.rjust(2, '0')
                        tot_testi = tot_testi.to_s.rjust(2, '0')
                        key = key.to_s.rjust(2, '0')
                        # udh=aabbcc: aa=id sequenza, bb=tot messaggi, cc=id del messaggio nella sequenza
                        udh = "#{sequence_index}#{tot_testi}#{key}"
                        id_messaggio_singolo = msg.id.to_s+sequence_index
                        uri_params = Spider::Messenger::Mobyt.parametri(username,password,to,from,testo,id_messaggio_singolo,operation,udh)
                        response = Spider::Messenger::Mobyt.do_post_request(uri, uri_params)
                        result = Spider::Messenger::Mobyt.check_response_http(response)
                    }

                else
                    uri_params = Spider::Messenger::Mobyt.parametri(username,password,to,from,text,msg.id.to_s)
                    response = Spider::Messenger::Mobyt.do_post_request(uri, uri_params)
                    result = Spider::Messenger::Mobyt.check_response_http(response)
                end

                if result
                    Spider.logger.debug("Sms inviato tramite Mobyt")
                    return true
                else
                    raise "Errore nell'invio degli sms."
                end

            else
                raise "Mobyt: credito insufficiente per mandare sms."
            end

                        
        end

    end



end; end; end; end    