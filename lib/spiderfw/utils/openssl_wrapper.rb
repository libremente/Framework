require 'openssl'

module Spider

    module OpenSslWrapper

    	#metodo che verifica che il file sia firmato e che sia stato generato dal file originale passato senza alterazioni
    	#ritorna un hash con una chave esito per capire se la verifica ha dato esito positivo e per ritornare o il
    	#messaggio d'errore o un hash con i dati dei certificati
    	def self.verify_p7m_short(original_file, signed_file)
    		signature = OpenSSL::PKCS7.new(File.read(signed_file))
			data = File.read(original_file)
			cert_store = OpenSSL::X509::Store.new
			cert_store.set_default_paths
			#estraggo il certificato con cui viene firmato
			certificati_firmatari = signature.certificates
			firmatari = signature.signers
			#OpenSSL::PKCS7::DETACHED
			esito = signature.verify(certificati_firmatari, cert_store, data, OpenSSL::PKCS7::NOVERIFY)
			if esito
				#array con i dati dei certificati dei firmatari
				array_cert_firmatari = []
				certificati_firmatari.each{ |certificato|
					hash_certificato = {}
					hash_certificato[:issuer] = {}
					certificato.issuer.to_a.each{ |item_of_name|
						hash_certificato[:issuer][item_of_name[0].to_sym] = item_of_name[1]
					} 
					hash_certificato[:subject] = {}
					certificato.subject.to_a.each{ |item_of_name|
						hash_certificato[:subject][item_of_name[0].to_sym] = item_of_name[1]
					} 
					hash_certificato[:serial] = certificato.serial
					hash_certificato[:not_after] = certificato.not_after
					hash_certificato[:not_before] = certificato.not_before
					array_cert_firmatari << hash_certificato
				}

				array_firmatari = []
				firmatari.each{ |firmatario|
					hash_firmatario = {}
					hash_firmatario[:issuer] = {}
					firmatario.issuer.to_a.each{ |item_of_name|
						hash_firmatario[:issuer][item_of_name[0].to_sym] = item_of_name[1]
					} 
					hash_firmatario[:name] = {}
					firmatario.name.to_a.each{ |item_of_name|
						hash_firmatario[:name][item_of_name[0].to_sym] = item_of_name[1]
					} 
					hash_firmatario[:serial] = firmatario.serial
					hash_firmatario[:signed_time] = firmatario.signed_time
					array_firmatari << hash_firmatario
				}
				{ :esito => 'true', :firmatari => array_firmatari, :certificati => array_cert_firmatari }
				
			else
				{ :esito => 'false', :error_string => signature.error_string }
				
			end
    	end


    end
end
