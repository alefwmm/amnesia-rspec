module Amnesia
  class Config
    class << self
      attr_accessor :enabled, :max_workers, :debug, :debug_server, :debug_webkit, :before_optimization, :require_cache
      attr_accessor :example_timeout, :example_group_timeout, :master_timeout, :reroute_io_for_spork, :at_init_block, :at_cleanup_block

      def at_init(&block)
        self.at_init_block = block
      end

      def at_cleanup(&block)
        self.at_cleanup_block = block
      end
    end
  end
end

