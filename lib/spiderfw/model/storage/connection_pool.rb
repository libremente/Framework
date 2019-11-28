require 'monitor'

module Spider; module Model; module Storage

    class ConnectionPool
        attr_reader :max_size
        attr_accessor :timeout, :retry

        def initialize(connection_params, provider)
            @connection_params = connection_params
            @provider = provider
            @connection_mutex = Monitor.new
            @queue = @connection_mutex.new_cond
            @max_size = Spider.conf.get('storage.pool.size')
            @max_size = provider.max_connections if provider.max_connections && provider.max_connections < @max_size
            @timeout = Spider.conf.get('storage.pool.timeout')
            @retry = Spider.conf.get('storage.pool.retry')
            @connections = []
            @free_connections = []
            @thread_connections = {}
        end
        
        def size
            @connections.length
        end
        
        def free_size
            @free_connections.length
        end
        
        def storage_type
            @provider.storage_type
        end

        def get_connection
            if Spider.conf.get('storage.shared_connection')
                @shared_conn ||= _checkout
                return @shared_conn
            end
            Thread.current[:storage_connections] ||= {}
            Thread.current[:storage_connections][storage_type] ||= {}
            @connection_mutex.synchronize do
                #Spider.logger.debug("DB Pool (#{Thread.current}): trying to get connection")
                if conn = Thread.current[:storage_connections][storage_type][@connection_params]
                    #Spider.logger.debug("DB Pool (#{Thread.current}): returning thread connection #{conn}")
                    @free_connections.delete(conn)
                    conn
                else
                    conn = _checkout
                    Thread.current[:storage_connections][storage_type][@connection_params] = conn
                    @thread_connections[Thread.current.object_id] = [conn, Time.now]
                    conn
                end
            end
        end
        
        def checkout
            @connection_mutex.synchronize do
                _checkout
            end
        end
        
        def release(conn)
            if Spider.conf.get('storage.shared_connection')
                return
            end
            @connection_mutex.synchronize do
                #Spider.logger.debug("DB Pool (#{Thread.current}): releasing #{conn}")
                @free_connections << conn
                Thread.current[:storage_connections][storage_type].delete(@connection_params)
                @thread_connections.delete(Thread.current.object_id)
                @queue.signal
            end
        end
        
        def remove(conn)
            @connection_mutex.synchronize do
                remove_connection(conn)
            end
        end
        
        def clear
            @connections.each do |c|
                @provider.disconnect(c)
            end
            @connections = []
            @free_connections = []
        end
        
        private
        
        def _release
        end
        
        def _checkout
            # Spider.logger.debug("DB Pool (#{Thread.current}): checkout (max: #{@max_size})")
            1.upto(@retry) do
                if @free_connections.empty?
                    # Spider.logger.debug("DB Pool (#{Thread.current}): no free connection")
                    if @connections.length < @max_size
                        create_new_connection
                    else
                        # metodo count_waiters non definito in ruby > 1.9.1
                        #Spider.logger.debug "#{Thread.current} WAITING FOR CONNECTION, #{@queue.count_waiters} IN QUEUE"
                        Spider.logger.debug "#{Thread.current} WAITING FOR CONNECTION"
                        unless @queue.wait(@timeout)
                            clear_stale_connections
                            create_new_connection if @free_connections.empty? && @connections.length < @max_size
                            if @free_connections.empty?
                                # metodo count_waiters non definito in ruby > 1.9.1
                                #Spider.logger.error "#{Thread.current} GOT TIRED WAITING, #{@queue.count_waiters} IN QUEUE"
                                Spider.logger.error "#{Thread.current} GOT TIRED WAITING"
                                raise StorageException, "Unable to get a #{storage_type} connection in #{@timeout} seconds" if @timeout
                            end
                        end
                    end
                else
                    # Spider.logger.debug("DB Pool (#{Thread.current}): had free connection")
                end
                conn = @free_connections.pop
                #Aggiunta da loris per ovviare ai problemi di interruzione di rete inaspettato
                #effettua il logoff della connessione se il ping non risponde
                conn.logoff if conn && !conn.ping
                while conn && !@provider.connection_alive?(conn)
                    Spider.logger.warn("Storage #{storage_type} Pool (#{Thread.current}): connection #{conn} dead")
                    remove_connection(conn)
                    conn = nil
                    conn = @free_connections.pop unless @free_connections.empty?
                end
                if conn
                    #Spider.logger.debug("DB Pool (#{Thread.current}): returning #{conn} (#{@free_connections.length} free)")
                    return conn
                end
            end
            raise StorageException, "#{Thread.current} unable to get a connection after #{@retry} retries."
        end
        
        def clear_stale_connections
            @connection_mutex.synchronize do
                keys = Set.new(@thread_connections.keys)
                Thread.list.each do |thread|
                    keys.delete(thread.object_id) if thread.alive?
                end
                keys.each do |thread_id|
                    conn, time = @thread_connections[thread_id]
                    Spider.logger.error("Thread #{thread_id} died without releasing connection #{conn} (acquired at #{time})")
                    if @provider.connection_alive?(conn)
                        @free_connections << conn
                    else
                        remove_connection(conn)
                    end
                    @thread_connections.delete(thread_id)
                end
                @thread_connections.each do |thread_id, conn_data|
                    conn, time = conn_data
                    diff = Time.now - time
                    if diff > 60
                        Spider.logger.warn("Thread #{thread_id} has been holding connection #{conn} for #{diff} seconds.")
                    end
                end
            end
        end
        
        def remove_connection(conn)
            @free_connections.delete(conn)
            @connections.delete(conn)
        end
        
        
        def create_new_connection
            conn = @provider.new_connection(*@connection_params)
            Spider.logger.debug("Storage #{storage_type } Pool (#{Thread.current}): creating new connection #{conn} (#{@connections.length} already in pool)")
            @connections << conn
            @free_connections << conn
        end



    end


end; end; end