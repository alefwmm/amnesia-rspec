module Amnesia
  module Logging
    def debug_state(msg)
      puts "[#{Process.pid}] #{self} #{msg}" if Config.debug
      $0 = "ruby #{self} #{msg}"
    end
  end
end