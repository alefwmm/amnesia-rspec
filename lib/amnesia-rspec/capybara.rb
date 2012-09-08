require 'unicorn'

module Amnesia
  def self.init_sessions
    # Kill old webkits that accumulate under Guard on dev stations..hacky hack hack
    `(uname -a |grep Darwin) && killall webkit_server`

    # Headless is needed for CI
    @headless = Headless.new(:display => Process.pid, :reuse => false)
    @headless.start

    @webkit_sessions = {}
    @default_session = Capybara::Session.new(Capybara.default_driver, Capybara.app).tap {|s| s.driver} # Driver is lazy-loaded

    Config.max_workers.times do |i|
      @token = :"token_#{i}"
      # Clear port each time or it'll keep trying to use the same one
      Capybara.run_server = false
      @webkit_sessions[@token] = Capybara::Session.new(:webkit, Capybara.app).tap {|s| s.driver} # Driver is lazy-loaded
      @counter_in.put @token
    end
    @token = nil
  end

  def self.cleanup
    @headless.destroy
  end

  def self.start_session(mode = nil)
    if mode == :webkit
      @session = @webkit_sessions[@token]
      @session.reset!
      orig = $0
      $0 = "ruby #{self} waiting for server"
      @session.driver.instance_eval { @rack_server.boot }
      $0 = orig
    else
      @session = @default_session
    end
  end

  def self.current_session
    @session
  end

  class AlwaysEqual
    def ==(whatever)
      true
    end
  end
end

RSpec.configure do |config|
  config.before(:really_each) do
    Amnesia.start_session(example.metadata[:js] && :webkit)
  end
end

module Capybara
  class Session
    def initialize_with_noise(mode, app=nil)
      puts "New Capybara::Session for #{mode}, #{app}"
      initialize_without_noise(mode, app)
    end
    alias_method_chain :initialize, :noise
  end

  class Server
    # Just assume they work, because we're going to actually finish booting them after when Capy would check
    def responsive_with_preload?
      if Amnesia.current_session
        responsive_without_preload?
      else
        true
      end
    end
    alias_method_chain :responsive?, :preload
  end

  def self.current_session
    Amnesia.current_session
  end
end

Capybara.server do |app, port|
  server = Unicorn::HttpServer.new(app)
  server.logger.level = Logger::WARN
  server.listen(port)
  class << server
    def master_pid # Must always == Process.ppid or worker loop will freak out and return
      Amnesia::AlwaysEqual.new
    end
  end
  server.instance_eval do
    worker_loop(Unicorn::Worker.new(1))
    puts "Worker exited, WTF!!"
  end
end

