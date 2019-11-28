require 'thin'
require 'spiderfw/http/adapters/rack'

module Spider; module HTTP
    
    class Thin < Server
        
        @supports = {
            :chunked_request => false
        }

        def options(opts)
            opts = super(opts)
            defaults = {
                :Host   => '0.0.0.0',
                :app    => 'spider'
            }
            return defaults.merge(opts)
        end


        def start_server(opts={})
            opts = options(opts)
            options = {
                :Port           => opts[:Port],
                :BindAddress    => opts[:Host]
            }
            @server = ::Thin::Server.start(opts[:Host], opts[:Port].to_i, Spider::HTTP::RackApplication.new) do 
                use Rack::CommonLogger
                use Rack::ShowExceptions
            end
        end

        def shutdown_server
            @server.stop
        end
        
    end
    
    
end; end