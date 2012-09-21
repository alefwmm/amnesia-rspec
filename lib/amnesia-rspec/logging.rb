module Amnesia
  module Logging
    class << self
      attr_accessor :prefix
    end

    def logging_with(obj)
      if obj.is_a?(RSpec::Core::Example)
        Logging.prefix = "#{obj.example_group.to_s} Example"
      else
        Logging.prefix = obj.to_s
      end
      Logging.prefix.sub!(/^.*ExampleGroup::/, "")
    end

    def self.prefix
      @prefix
    end

    def debug(msg)
      puts "[#{Process.pid}] #{Logging.prefix} #{msg}" if Config.debug
    end

    def debug_state(msg)
      debug msg
      $0 = "ruby #{Logging.prefix} #{msg}"
    end
  end
end