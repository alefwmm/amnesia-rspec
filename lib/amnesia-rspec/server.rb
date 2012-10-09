module Amnesia
  class Server
    class Stop < Exception; end

    def initialize(app, port)
      @mutex = Mutex.new
      @port = port
      @server = Unicorn::HttpServer.new(app)
      @server.logger.level = Logger::WARN
      @socket = @server.listen(port)
      #### From init_worker_process
      @server.instance_eval do
        build_app! unless preload_app
      end
    end

    def start
      @mutex.synchronize do
        raise "WTF?!" if @thread
        @thread = Thread.new do
          begin
            clear # Make sure not to process any leftover requests from after we last stopped
            @stopping = @handling_request = false
            run_loop
          rescue => ex
            puts ex #if Config.debug_server
            puts ex.backtrace #if Config.debug_server
          end
        end
      end
    end

    def stop
      @mutex.synchronize do
        puts "[#{Process.pid}] {#{@port}} requesting stop for #{@thread.inspect}" if Config.debug_server
        catch (:stopped) do
          # First ask nicely
          @stopping = true
          sleep 0.01
          throw :stopped unless @thread.alive?
          if @handling_request
            # We don't want to interrupt the middle of a request if we can help it, produces really unpredictable behavior
            5.times do
              puts "[#{Process.pid}] {#{@port}} waiting for request in #{@thread.inspect}" #if Config.debug_server
              sleep 1
              throw :stopped unless @thread.alive?
            end
          end
          while true
            @thread.raise Stop
            10.times do
              sleep 0.01
              throw :stopped unless @thread.alive?
              puts "[#{Process.pid}] {#{@port}} waiting for #{@thread.inspect} to die" if Config.debug_server
            end
            puts "[#{Process.pid}] {#{@port}} #{@thread.inspect} really doesn't want to die" # if Config.debug_server
          end
        end
        @thread = nil
      end
    end

    private
    def clear
      while @socket.kgio_tryaccept
        puts "[#{Process.pid}] {#{@port}} discarding request in #{@thread.inspect}" #if Config.debug_server
      end
    end

    def run_loop
      begin
        port = @port
        sock = @socket
        puts "[#{Process.pid}] {#{port}} entering loop in #{@thread.inspect}" if Config.debug_server

        #### From worker_loop, very vaguely
        begin
          while client = sock.kgio_tryaccept
            #puts "[#{Process.pid}] {#{port}} got request" if Config.debug_server
            @handling_request = true
            # Check @stopping here to avoid race condition with #stop, since it checks @handling_request after setting @stopping
            break if @stopping
            @server.instance_eval { process_client(client) }
            @handling_request = false
          end

          IO.select([sock])
        rescue Errno::EBADF
          puts "[#{Process.pid}] {#{port}} EBADF" if Config.debug_server
          return
        rescue => e
          Unicorn.log_error(@logger, "listen loop error", e)
        end while not @stopping
      rescue Stop
        puts "[#{Process.pid}] {#{port}} got stop in #{@thread.inspect}" if Config.debug_server
      end
      puts "[#{Process.pid}] {#{port}} exiting from loop in #{@thread.inspect}" if Config.debug_server
    end
  end
end