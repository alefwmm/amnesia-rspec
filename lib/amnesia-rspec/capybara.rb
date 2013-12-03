require 'unicorn'
require 'amnesia-rspec/server'

module Amnesia
  def self.init_sessions
    # Kill old webkits that accumulate under Guard on dev stations..hacky hack hack
    `(uname -a |grep Darwin) && killall webkit_server`

    # Headless is needed for CI
    @headless = Headless.new(:display => Process.pid, :reuse => false)
    @headless.start

    @webkit_sessions = {}
    @servers = {}
    @default_session = Capybara::Session.new(Capybara.default_driver, Capybara.app)

    Config.max_workers.times do |i|
      @token = "token_#{i}"
      init_session
      seed_token @token
    end
    @token = nil
  end

  def self.init_session
    Capybara::Server.instance_eval { @ports = {} } # Reset each time or it'll pick the same port
    @webkit_sessions[@token] = Capybara::Session.new(:webkit, Capybara.app).tap do |s|
      # In the current scheme of things, we boot a webkit server for each session usage, so kill the initial one
      s.driver.browser.instance_eval { @connection.instance_eval { Process.kill("KILL", @pid) } }
    end
    until booting_server_registered?
      puts "Waiting for server to register for #{@token}"
      sleep 0.01
    end
  end

  def self.booting_server_registered?
    @servers[@token]
  end

  def self.cleanup
    @headless.destroy
  end

  def self.register_server(app, port)
    @servers[@token] = Amnesia::Server.new(app, port)
    puts "Server registered for #{@token}"
  end

  def self.start_session(mode = nil)
    if mode == :webkit
      return if javascript? # Already set up
      @session = @webkit_sessions[@token]
      # Just start up a new browser each time, it's fast and reduces flakiness
      @session.driver.instance_eval do
        @browser = Capybara::Webkit::Browser.new(Capybara::Webkit::Connection.new)
        @browser.enable_logging if Config.debug_webkit
      end
      @server = @servers[@token]
      @server.start
      orig = $0
      $0 = "#{$0} waiting for server"
      while true
        sleep 0.02
        begin
          if @session.server.responsive?
            break
          end
        rescue Timeout::Error
        rescue => ex
          puts "[#{Process.pid}] {#{@server.port}} Error while waiting for server: #{ex}"
        end
        puts "[#{Process.pid}] {#{@server.port}} Waiting for server.."
      end
      $0 = orig
      restore_external_session_state
    else
      @session = @default_session
    end
  end

  # Check if the server recorded errors via Capybara Rack Middleware; run in after_each, inside the RWF work,
  # unlike stop_session whose errors would be reported as an Amnesia failure, rather than a spec failure
  def self.check_for_server_errors!
    if javascript?
      raise @session.server.error if Capybara.raise_server_errors and @session.server.error
    end
  end

  def self.stop_session
    if javascript?
      @session.driver.browser.instance_eval { @connection.instance_eval { Process.kill("KILL", @pid) } }
      @server.stop
      @server = nil
    end
    @session = nil
  end

  # Actually, we want to save this for rack_test, too, so "external" is misleading; but we restore it externally to webkit
  def self.save_external_session_state
    if @session
      @previous_url = (u = @session.driver.browser.current_url) && u =~ /:\/\/[^\/]*(\/.*)/ && $1
      if @session == @default_session
        @previous_cookies = @session.driver.browser.current_session.instance_eval {@rack_mock_session.cookie_jar}.to_hash.map do |k, v|
          "#{k}=#{v}; HttpOnly; domain=127.0.0.1; path=/"
        end
      else
        @previous_cookies = @session.driver.browser.get_cookies
      end
      #puts "Saved path: #{@previous_url}"
    end
  end

  def self.restore_external_session_state
    if @previous_cookies
      #puts "Had cookies: #{@session.driver.browser.get_cookies.inspect}"
      #puts "Restoring cookies: \n\t#{@previous_cookies.join("\n\t")}"
      @previous_cookies.each {|c| @session.driver.browser.set_cookie(c)}
      #puts "Have cookies: #{@session.driver.browser.get_cookies.inspect}"
    end
    if @previous_url
      #puts "Restoring path: #{@previous_url}"
      begin
        @session.visit @previous_url
      rescue Capybara::Webkit::InvalidResponseError => ex
        puts "Warning: error restoring URL '#{@previous_url}': #{ex}"
      end
    end
  end

  def self.current_session
    @session
  end

  def self.javascript?
    @session && @session != @default_session && @server
  end

  class AlwaysEqual
    def ==(whatever)
      true
    end
  end
end

# This is a whole bunch of retardedness to fix the fact that set_cookie always prepends a ., thereby interfering
# with Rails's ability to subsequently overwrite restored cookies ::facepalm::
class CookieFixerApp
  def initialize(app)
    @app = app
  end

  def call(env)
    #puts "[#{Process.pid}] #{env['PATH_INFO']}"
    result = @app.call(env)
    if Amnesia.javascript? && result[1]["Set-Cookie"]
      #puts result[1]["Set-Cookie"]
      result[1]["Set-Cookie"].gsub!(/; HttpOnly/, "; domain=.127.0.0.1; HttpOnly")
      #puts result[1]["Set-Cookie"]
    end
    result
  end
end
Capybara.app = CookieFixerApp.new(Capybara.app)

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
      elsif !Amnesia.booting_server_registered?
        # Capybara won't start the server unless it's not responsive; so force false until the server registers with us
        false
      else
        true
      end
    end
    alias_method_chain :responsive?, :preload

    # Otherwise responsive? will whine about our thread being dead after forking
    def boot_with_clear_server_thread
      boot_without_clear_server_thread.tap do
        @server_thread = nil
      end
    end
    alias_method_chain :boot, :clear_server_thread
  end

  def self.current_session
    Amnesia.current_session
  end
end

Capybara.server do |app, port|
  begin
    Amnesia.register_server(app, port)
  rescue => ex
    puts ex
    puts ex.backtrace
  end
end

module Capybara::Webkit
  class Browser
    # Prevent from hanging indefinitely on read from browser
    def check_with_timeout
      begin
        Timeout::timeout(90) do
          check_without_timeout
        end
      rescue TimeoutError
        raise "Timed out waiting for response from Webkit"
      end
    end
    alias_method_chain :check, :timeout
  end

  class Driver
    # current_url will fail if we haven't visited anything, so keep track of whether we have
    def current_url_with_safety
      if @last_visited
        current_url_without_safety
      end
    end
    def visit_with_safety(path)
      @last_visited = path
      visit_without_safety(path)
    end
    def reset_with_safety!
      @last_visited = nil
      reset_without_safety!
    end
    [:current_url, :visit, :reset!].each {|m| alias_method_chain m, :safety}
  end
end

