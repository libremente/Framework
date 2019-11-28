require 'base64'
require 'uuidtools'
require 'digest/md5'
require 'macaddr'
require 'spiderfw/http/http'

module Spider; module ControllerMixins
    
    module HTTPMixin
        
        def self.included(klass)
            klass.extend(ClassMethods)
        end
        
        # Sets the headers to redirect the browser to the given url, and calls
        # {Controller#done} to terminate the execution of the Controller chain
        # @param [String] url
        # @param [Fixnum] code HTTP status to send
        # @return void
        def redirect(url, code=Spider::HTTP::SEE_OTHER)
            debug "REDIRECTING TO #{url}"
            @request.session.persist if @request.session # It might be too late afterwards
            @response.status = code
            @response.headers["Location"] = url
            @response.headers.delete("Content-Type")
            @response.headers.delete("Set-Cookie")
            done
        end
        
        # Takes a url path that the framework would accept, and transforms it
        # into the url path the webserver would send, given the settings in http.proxy_mapping
        # @param [Strint] url_path
        # @return [String] The transformed url path
        def self.reverse_proxy_mapping(url_path)
            return '' unless url_path
            if (maps = Spider.conf.get('http.proxy_mapping'))
                maps.each do |proxy, spider|
                    spider ||= ''
                    return proxy + url_path[spider.length..-1] if (spider == "" || url_path[0..spider.length-1] == spider)
                end
            end
            return url_path
        end
        
        # Returns the http path used to call the current controller & action.
        # Reverses any proxy mappings to the Controller#request_path.
        # @return [String]
        def request_path
            HTTPMixin.reverse_proxy_mapping(super)
        end
        
        # @return [String] the request_path prefixed with http:// and the current host.
        def request_url
            return request_path unless @request.env['HTTP_HOST']
            #'http://'+@request.env['HTTP_HOST']+request_path  vecchia versione con problemi con https
            if @request.env["HTTPS"] == "on" || @request.env['HTTP_X_FORWARDED_PROTO'] == 'https' || Spider.conf.get('site.ssl') # uso anche il parametro HTTP_X_FORWARDED_PROTO per reverse_proxy con ssl_offloading
                u = "https://#{@request.env['HTTP_HOST']}#{request_path}"
            else
                u = "http://#{@request.env['HTTP_HOST']}#{request_path}"
            end
            u
        end
        
        # @return [String] the request_url with query params, if any
        def request_full_url
            url = request_url
            if (@request.env['QUERY_STRING'] && !@request.env['QUERY_STRING'].empty?)
                url += '?'+@request.env['QUERY_STRING']
            end
            return url
        end
        
        # Sets or returns the charset for the controller
        # @param [String|nil] The charset
        # @return [String] The charset in use
        def self.output_charset(val=nil)
            @output_charset = val if val
            @output_charset || Spider.conf.get('http.charset')
        end
        
        # Sets a Content type
        # @param [String|Symbol] Content type, or a symbol representing it
        #                        (Can be :text, :json, :js, :javascript, :html, :xml)
        # @return [String] The value of the "Content-Type" header
        def content_type(ct)
            if ct.is_a?(Symbol)
                ct = {
                    :text       => 'text/plain',
                    :json       => 'application/json',
                    :js         => 'application/x-javascript',
                    :javascript => 'application/x-javascript',
                    :html       => 'text/html',
                    :xml        => 'text/xml'
                }[ct]
            end
            @response.headers["Content-Type"] = "#{ct};charset=utf-8"
        end
        
        # 
        # @param [String] action
        # @param [*Object] arguments
        def before(action='', *arguments)
            return super if self.is_a?(Spider::Widget)
             # FIXME: the Spider::Widget check
            # is needed because with _wt the widget executes without action
            # Redirect to url + slash if controller is called without action
            dest = HTTPMixin.reverse_proxy_mapping(@request.env['PATH_INFO'])
            if (action == '' && dest[-1].chr != '/' && !self.is_a?(Spider::Widget))
                dest = dest += '/'
                if (@request.env['QUERY_STRING'] && !@request.env['QUERY_STRING'].empty?)
                    dest += '?'+@request.env['QUERY_STRING']
                end
                redirect(dest)
            end
            super
        end
        
        # @return [String] the base URL to which the installation responds
        def self.base_url
            HTTPMixin.reverse_proxy_mapping("")
        end
        
        # @return [String] the base URL to which the installation responds
        def base_url
            HTTPMixin.base_url
        end


        def prepare_scene(scene)
            scene = super
            scene.base_url = base_url
            scene.controller[:request_url] = request_url
            return scene
        end
        
        def try_rescue(exc)
            if (exc.is_a?(Spider::Controller::NotFound))
                @response.status = Spider::HTTP::NOT_FOUND
            elsif (exc.is_a?(Spider::Controller::BadRequest))
                @response.status = Spider::HTTP::BAD_REQUEST
            elsif (exc.is_a?(Spider::Controller::Forbidden))
                @response.status = Spider::HTTP::FORBIDDEN
            elsif (exc.is_a?(HTTPStatus))
                @response.status = exc.code
                Spider::Logger.debug("Sending HTTP status #{exc.code}")
                return
            else
                @response.status = Spider::HTTP::INTERNAL_SERVER_ERROR
            end
            super
        end
        
        def challenge_basic_auth()
            realm ||= http_auth_realm
            realm ||= 'Secure Area'
            @response.headers["WWW-Authenticate"] = "Basic realm=\"#{realm}\""
            @response.status = Spider::HTTP::UNAUTHORIZED
            render('errors/unauthorized') if self.is_a?(Visual)
            done
        end
        
        def check_basic_auth(authenticator)
            if (@request.env['HTTP_AUTHORIZATION'] =~ /Basic (.+)/)
                pair = Base64.decode64($1)
                user, pass = pair.split(':')
                return authenticator.authenticate(:login, {:username => user, :password => pass})
            end
        end
        
        def challenge_digest_auth(realm=nil)
            realm ||= http_auth_realm
            realm ||= 'Secure Area'
            
            # nonce
            now = "%012d" % @request.request_time
            pk  = Digest::MD5.hexdigest("#{now}:#{digest_instance_key}")[0,32]
            nonce = [now + ":" + pk].pack("m*").chop # it has 60 length of chars.
            
            opaque = [UUIDTools::UUID.random_create.to_s].pack("m*").chop
            header = "Digest realm=\"#{realm}\", qop=\"auth\", nonce=\"#{nonce}\", opaque=\"#{opaque}\""
            @response.headers['WWW-Authenticate'] = header
            @response.status = Spider::HTTP::UNAUTHORIZED
            done
        end
        
        def check_digest_auth(authenticator)
            # TODO: implement opaque, auth-int
            if (@request.env['HTTP_AUTHORIZATION'] =~ /Digest (.+)/)
                parts = $1.split(',')
                params = {}
                parts.each do |p|
                    k, v = p.strip.split('=')
                    v = v.sub(/^"+/, '').sub(/"+$/, '')
                    params[k.downcase] = v
                end
                ['username', 'realm', 'nonce', 'uri', 'cnonce', 'qop', 'nc', 'response', 'opaque'].each{ |k| return unless params[k] }
                user = params['username']
                user = $1 if params['username'] =~ /.+\\(.+)/ # FIXME: Temp fix for windows sending DOMAIN/User
                pub_time, pk = params['nonce'].unpack("m*")[0].split(":", 2)
                return unless pub_time && pk
                return unless Digest::MD5.hexdigest("#{pub_time}:#{digest_instance_key}")[0,32] == pk
                diff_time = @request.request_time.to_i - pub_time.to_i
                return if diff_time < 0
                return if diff_time > Spider.conf.get('http.nonce_life')
                user = authenticator.load(:username => user, :realm => params['realm'])
                return unless user
                ha1 = user.ha1
                return unless ha1
                ha2 = Digest::MD5.hexdigest("#{@request.env['REQUEST_METHOD']}:#{params['uri']}")
                if (params['qop'] == "auth" || params['qop'] == "auth-int")
                    param2 = ['nonce', 'nc', 'cnonce', 'qop'].map{|key| params[key] }.join(':')
                    response = Digest::MD5.hexdigest([ha1, param2, ha2].join(':'))
                else
                    response = Digest::MD5.hexdigest([ha1, params['nonce'], ha2].join(':'))
                end
                # FIXME: temporaneamente disabilitato controllo perché con il login DOMINIO/Utente non corrisponde
                #return unless response == params['response']
                return user
            end
        end
        
        def digest_instance_key
            Digest::MD5.hexdigest("#{Mac.addr}:plaw15x857m4p671")
        end
        
        
        
        def http_auth_realm=(val)
            @http_auth_realm = val
        end
        
        def http_auth_realm
            @http_auth_realm || self.class.http_auth_realm
        end
        
        module ClassMethods

            def http_auth_realm(val=nil)
                @http_auth_realm = val if val
                @http_auth_realm
            end
            
            
            def url(action=nil)
                return super unless Spider.site
                u = "http://#{Spider.site.domain}"
                u += ":#{Spider.site.port}" unless Spider.site.port == 80
                u += HTTPMixin.reverse_proxy_mapping(super(action))
                u
            end

            def http_url(action=nil)
                url(action)
            end
            
        end
        
        class HTTPStatus < RuntimeError
            
            class << self
                
                def method_missing(meth, *args)
                    if (Spider::HTTP::StatusCodes.const_defined?(meth))
                        return self.new(Spider::HTTP::StatusCodes.const_get(meth))
                    end
                    super
                end
                
            end
            
            attr_reader :code
            
            def initialize(code)
                @code = code
            end
            
            def status_message
                Spider::HTTP.status_messages[@code]
            end
        end

        
    end
    
    
    
end; end
