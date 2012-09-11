require "amnesia-rspec/version"
require "amnesia-rspec/logging"
require "amnesia-rspec/rspec_hooks" # Always need to patch RSpec a little, to enable :really_each

module Amnesia
  extend Logging

  class Config
    class << self
      attr_accessor :enabled, :max_workers, :debug, :debug_server, :before_optimization
    end
  end

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

    # Important to use :DGRAM here so don't get more than one token out per read
    # Probably no real need for Cod here
    @counter_in = Cod::Pipe.new(nil, Socket.socketpair(:UNIX, :DGRAM, 0))
    @counter_out = @counter_in.dup

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
        orig = $0
        $0 = "#{orig} waiting for lock"
        f.flock(File::LOCK_EX)
        $0 = "#{orig} holding lock"
        yield
        $0 = "#{orig} releasing lock"
        f.flock(File::LOCK_UN)
        $0 = orig
      end
    #end
  end

  def self.wait(nice = 0)
    unless @token
      @token = @counter_out.get
      # If we're being nice, give someone else a chance first
      nice.times do
        @counter_in.put @token
        sleep 0.001
        @token = @counter_out.get
      end
      puts "[#{Process.pid}] #{self} got token" if Config.debug
    end
  end

  def self.signal
    return unless @token
    stop_session # Make sure we're not going to accept any connections after putting token
    @counter_in.put @token
    @token = nil
    puts "[#{Process.pid}] #{self} put token" if Config.debug
  end

  def self.in_child
    save_external_session_state
    stop_session
    child = Process.fork do
      monitor_parent
      yield
    end
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
        #puts "[#{Process.pid}] #{self} exiting, dead parent"
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

#Kernel.class_eval do
#  def load_with_noise(*args)
#    puts "Load: " + args.inspect if load_without_noise(*args)
#  end
#  alias_method_chain :load, :noise
#  def require_with_noise(*args)
#    puts "Require: " + args.inspect if require_without_noise(*args)
#  end
#  alias_method_chain :require, :noise
#end



