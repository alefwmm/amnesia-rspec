module Amnesia
  class Server
    class Stop < Exception; end

    def initialize(app, port)
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
      raise "WTF?!" if @thread
      @thread = Thread.new do
        begin
          run_loop
        rescue => ex
          puts ex if Config.debug_server
          puts ex.backtrace if Config.debug_server
        end
      end
    end

    def stop
      puts "[#{Process.pid}] {#{@port}} requesting stop for #{@thread.inspect}" if Config.debug_server
      @thread.raise Stop
      sleep 0
      n = 0
      while @thread.alive?
        n += 1
        puts "[#{Process.pid}] {#{@port}} waiting for #{@thread.inspect} to die" if Config.debug_server
        @thread.raise Stop if n % 10 == 0
        sleep 0.01
      end
      @thread = nil
    end

    private
    def run_loop
      begin
        @thread = Thread.current
        port = @port
        sock = @socket
        puts "[#{Process.pid}] {#{port}} entering loop in #{@thread.inspect}" if Config.debug_server

        #### From worker_loop, very vaguely
        @server.instance_eval do
          begin
            while client = sock.kgio_tryaccept
              #puts "[#{Process.pid}] {#{port}} got request" if Config.debug_server
              process_client(client)
            end

            IO.select([sock])
          rescue Errno::EBADF
            puts "[#{Process.pid}] {#{port}} EBADF" if Config.debug_server
            return
          rescue => e
            Unicorn.log_error(@logger, "listen loop error", e)
          end while true
        end
      rescue Stop
        puts "[#{Process.pid}] {#{port}} exiting from loop in #{@thread}" if Config.debug_server
      end
    end
  end
end