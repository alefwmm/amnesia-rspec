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
    @default_session = Capybara::Session.new(Capybara.default_driver, Capybara.app).tap {|s| s.driver} # Driver is lazy-loaded

    Config.max_workers.times do |i|
      @token = :"token_#{i}"
      Capybara::Server.instance_eval { @ports = {} } # Reset each time or it'll pick the same port
      @webkit_sessions[@token] = Capybara::Session.new(:webkit, Capybara.app).tap {|s| s.driver} # Driver is lazy-loaded
      @counter_in.put @token
      until @servers[@token]
        puts "Waiting for server to register for #{@token}"
        sleep 0.01
      end
    end
    @token = nil
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
      @server = @servers[@token]
      @server.start
      @session = @webkit_sessions[@token]
      @session.reset!
      orig = $0
      $0 = "#{$0} waiting for server"
      while true
        begin
          if @session.driver.instance_eval { @rack_server.responsive? }
            break
          end
        rescue => ex
          puts "[#{Process.pid}] Error while waiting for server: #{ex}"
        end
        puts "Waiting for server.."
        sleep 0.02
      end
      $0 = orig
      restore_external_session_state
    else
      @session = @default_session
    end
  end

  def self.stop_session
    @server.stop if @server
    @session = @server = nil
  end

  # Actually, we want to save this for rack_test, too, so "external" is misleading; but we restore it externally to webkit
  def self.save_external_session_state
    if @session
      @previous_url = @session.current_path if @session.driver.current_url
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
        @session.driver.visit @previous_url
      rescue Capybara::Driver::Webkit::WebkitInvalidResponseError => ex
        puts "Warning: error restoring URL '#{@previous_url}': #{ex}"
      end
    end
  end

  def self.current_session
    @session
  end

  def self.javascript?
    @session && @session != @default_session
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
  begin
    Amnesia.register_server(app, port)
  rescue => ex
    puts ex
    puts ex.backtrace
  end
end

class Capybara::Driver::Webkit
  class Browser
    # Prevent from hanging indefinitely on read from browser
    def check_with_timeout
      Timeout::timeout(90) do
        check_without_timeout
      end
    end
    alias_method_chain :check, :timeout
  end

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

