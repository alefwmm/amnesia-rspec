module Amnesia
  class Config
    class << self
      attr_accessor :enabled, :max_workers, :debug, :debug_server, :before_optimization, :require_cache
    end
  end
end

