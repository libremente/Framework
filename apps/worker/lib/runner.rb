require 'rufus/scheduler'

module Spider; module Worker
    
    
    class Runner
        
        def initialize
            if Gem.loaded_specs['rufus-scheduler'].version.to_s < "3.0.0"
                @scheduler = Rufus::Scheduler.start_new
            else
                @scheduler = Rufus::Scheduler.new
            end
        end
        
        def stop
            @scheduler.stop
        end
        
        def join
            @scheduler.join
        end
        
        def every(time, params=nil, &proc)
            if (params)
                @scheduler.every(time) do
                    params[:obj].send(params[:method], *params[:arguments])
                end
            else
                @scheduler.every(time, &proc)
            end
        end
        
        def cron(time, params=nil, &proc)
            if (params)
                @scheduler.cron(time) do
                    params[:obj].send(params[:method], *params[:arguments])
                end
            else
                @scheduler.cron(time, &proc)
            end
        end
        
    end
    
    
end; end