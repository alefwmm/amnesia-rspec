require "amnesia-rspec/version"
require "amnesia-rspec/config"
require "amnesia-rspec/logging"
require "amnesia-rspec/rspec_hooks" # Always need to patch RSpec a little, to enable :really_each

module Amnesia
  extend Logging

  def self.forkit_and_forget!
    Config.enabled = true
    yield Config

    raise "Amnesia max workers set to #{Config.max_workers}" unless Config.max_workers > 0

    # Stuff of our own; no point loading unless we're running
    require 'amnesia-rspec/cod_proxy'
    require 'amnesia-rspec/run_with_fork'

    # Monkeypatch away!
    require 'amnesia-rspec/active_record'
    require 'amnesia-rspec/rspec'
    require 'amnesia-rspec/capybara'
    require 'amnesia-rspec/factory_girl'

    ######## Initialize singleton stuff

    @lockfile = Tempfile.new("amnesia.lock")

    @killpipe_r, @killpipe_w = IO.pipe
    @iopipe_r, @iopipe_w = IO.pipe

    RSpec.configure do |config|
      if Spork.using_spork?
        config.output_stream = config.error_stream = IO.for_fd(2, "a")
      end
    end

    load "#{Rails.root.to_s}/db/schema.rb"
    ActiveRecord::Base.connection.cache_schema_info!
    Dir[Rails.root.join("spec/factories/**/*.rb")].each { |f| load f }
    FixtureHelpers.reload_fixtures
    Amnesia.init_sessions
  end

  def self.safe_write
    # Time limit this to avoid/detect deadlocks
    #Timeout::timeout(5) do
      # Each child needs its own FD for lock to be effective, so just open it newly each time
      File.open(@lockfile.path, "r") do |f|
        #orig = $0
        #$0 = "#{orig} waiting for lock"
        f.flock(File::LOCK_EX)
        #$0 = "#{orig} holding lock"
        yield
        #$0 = "#{orig} releasing lock"
        f.flock(File::LOCK_UN)
        #$0 = orig
      end
    #end
  end

  def self.add_token_channel
    @token_out_channels ||= []
    @token_in_channel.close if @token_in_channel # Only keep one per fork-level
    @token_in_channel, s_out = Socket.socketpair(:UNIX, :DGRAM, 0)
    @token_out_channels << s_out
  end

  def self.seed_token(token)
    unless @token_out_channels
      # Initialize the token setup
      add_token_channel
      @global_token_in_channel = @token_in_channel
      @token_in_channel = nil # Avoid global channel being closed
    end
    @token_out_channels.first.send(token, 0)
  end

  MAX_TOKEN_LEN = 10

  def self.wait
    unless @token
      begin
        ready = IO.select([@token_in_channel, @global_token_in_channel])[0]
        if ready.length == 2
          # Prefer local token if available
          channel = @token_in_channel
        else
          channel = ready.first
        end
        @token = channel.recv_nonblock(MAX_TOKEN_LEN)
      rescue Errno::EAGAIN
        retry
      end
      debug "got token #{@token} from #{channel.inspect}" if Config.debug
    end
  end

  def self.signal
    begin
      begin
        Timeout::timeout(120) do
          stop_session # Make sure we're not going to accept any connections after putting token
        end
      rescue => ex
        puts "[#{Process.pid}] Error while stopping session, will retry: #{ex.inspect}"
        puts ex.backtrace
        retry
      end

      # We're done working, check for any tokens on our private incoming channel, then close it
      tokens = [@token].compact
      begin
        Timeout::timeout(15) do
          while token = @token_in_channel.recv_nonblock(MAX_TOKEN_LEN)
            if token.length > 0
              tokens << token
              debug "found token #{token} in #{@token_in_channel.inspect}" if Config.debug
            else
              break
            end
          end
        end
      rescue Errno::EAGAIN
      rescue Timeout::Error
        puts "[#{Process.pid}] Hung during supposedly nonblocking recv, WTF"
      end
      @token_in_channel.close
      # Pass our first token upstream as little as possible, but not to ourselves
      @token_out_channels.pop
      begin
        out = @token_out_channels.pop
        while tokens.length > 0
          token = tokens.first
          debug "putting token #{token} into #{out.inspect}" if Config.debug
          out.send(token, 0)
          tokens.shift
          # Successfully sent one, now try to send rest to either top-level child or global
          if @token_out_channels.length > 1
            out = @token_out_channels[1] # Channel for top-level child
            @token_out_channels.slice!(0,1) # Only try global on next retry
          end
        end
      rescue SystemCallError => ex
        debug "#{ex.inspect}" if Config.debug
        if @token_out_channels.length > 0
          retry
        else
          puts "[#{Process.pid}] Ran out of places to put a token! Was trying #{out.inspect} got: #{ex.inspect}"
        end
      end
    rescue => ex
      puts "[#{Process.pid}] #{ex.inspect}"
      puts ex.backtrace
    end
  end

  def self.in_child
    save_external_session_state
    stop_session
    child = Process.fork do
      sleep 0.001 # Sleeping a moment after forking seems to avoid random crashes
      add_token_channel
      monitor_parent
      yield
    end
    sleep 0.001 # Sleeping a moment after forking seems to avoid random crashes
    @token = nil
    Process.detach(child)
  end

  # This is needed so that once the original parent exits, all the children get killed too, not left hanging around
  def self.monitor_parent
    begin
      @killpipe_w.close
    rescue IOError
    end
    Thread.new do
      begin
        @killpipe_r.read
      ensure
        #debug "exiting, dead parent"
        exit!
      end
    end
    # Give the above thread a moment to start up before proceeding; there's some sort of ugly race condition where
    # if the above read doesn't happen before we attempt to flock for Cod, interpreter crash or other strange behavior
    # occurs
    sleep 0.001
  end

  def self.run_iopipe
    puts "Crazy IO routing for Spork activated."
    Thread.new do
      while true
        puts @iopipe_r.gets
      end
    end
  end

  def self.output
    @iopipe_w
  end
end



