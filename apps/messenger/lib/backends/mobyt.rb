#require "digest/md5"
require "net/http"
require "iconv" if RUBY_VERSION =~ /1.8/

module Spider::Messenger

      module Mobyt

            # def self.parametri(username,password,to,from,testo,operation="TEXT",udh="")
            #       #cambio la codifica per gli accenti e caratteri particolari
            #       if RUBY_VERSION =~ /1.8/
            #         testo_codificato = Iconv.conv('ISO-8859-15', 'UTF-8', testo)
            #       else
            #         testo_codificato = testo.encode('ISO-8859-15', 'UTF-8')
            #       end
            #       string_digest = [username, operation, to, from, testo_codificato, password].map{ |val|
            #           val.to_s 
            #       }.join("")
            #       ticket = Digest::MD5.hexdigest(string_digest).downcase
            #       hash_parametri = {
            #           'rcpt'       => to, 
            #           'operation'  => operation,
            #           'from'       => from,
            #           'data'       => testo_codificato,
            #           'id'         => username,
            #           'qty'        => "h",
            #           'ticket'     => ticket,
            #           'udh'        => udh         
            #       }

            # end

            def self.parametri(username,password,to,from,testo,message_id,operation="TEXT",udh="")                 
                hash_parametri = {
                    'login'             => username,
                    'password'          => password,
                    'message_type'      => 'L', 
                    'recipient'         => to,
                    'sender'            => from,
                    'message'           => testo,
                    'order_id'          => message_id       
                }

            end

            def self.getCredit
                url_credit = "http://app.mobyt.it/Mobyt/CREDITS"
                login = Spider.conf.get('messenger.mobyt.username')
                password = Spider.conf.get('messenger.mobyt.password')
                query_string = "login=#{login}&password=#{password}"
                response = Net::HTTP.get(URI.parse(url_credit+'?'+query_string))
                if response =~ /^OK/
                    true
                else
                    false
                end
            end

            def self.do_post_request(uri,data)
                  response = Net::HTTP.post_form(uri,data) 
            end

            def self.check_response_http(response)
                case response
                when Net::HTTPSuccess
                    if response.body !~ /^OK/
                        raise response.body.to_s
                    else
                        return true 
                    end
                else
                    #solleva un eccezione
                    raise response.class.to_s
                end
                return false         
            end

      end      

end