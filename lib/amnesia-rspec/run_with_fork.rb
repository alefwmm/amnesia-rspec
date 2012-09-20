module Amnesia
  module RunWithFork
    def run_with_fork(options = {})
      include Amnesia::Logging

      define_method :run_with_child do |*args, &block|
        debug_state "run_with_child"
        if options[:master]
          logging_with(self)
          if Config.require_cache
            require 'amnesia-rspec/require_cache'
            RequireCache.activate!
          end
          GC.start
          sleep 1 # Need to wait for it to finish? Should test if this makes any difference
          GC.disable
          proxy = CodProxy.new(self) # reporter
          proxy_block = ->(reporter) do
            block.call(proxy)
          end
          Amnesia.run_iopipe if Spork.using_spork?
          #puts "***************** First fork *******************"
        else # If we're not in charge here, we need a token to run
          debug_state "waiting for token"
          Amnesia.wait
        end
        debug_state "parent starting child"
        Amnesia.in_child do
          begin
            logging_with(self)
            if Spork.using_spork?
              $stdout = STDOUT.reopen(Amnesia.output)
              $stderr = STDERR.reopen(Amnesia.output)
            end
            debug_state "child started"
            run_without_child(*args, &(proxy_block || block))
            debug_state "child finished"
          rescue => ex
            puts [ex.inspect, ex.backtrace].join("\n\t")
          ensure
            debug_state "child exiting"
            Amnesia.signal
            exit!(true)
          end
        end
        # Parent
        if proxy # Root level process receiving results
          debug_state "parent waiting for proxy"
          proxy.run_proxy_to_end
          Amnesia.cleanup
        end
        debug_state "parent resumed"
      end
      alias_method_chain :run, :child
    end
  end
end