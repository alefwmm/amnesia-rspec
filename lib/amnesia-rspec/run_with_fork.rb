module Amnesia
  module RunWithFork
    def run_with_fork(options = {})
      include Amnesia::Logging

      define_method :run_with_child do |*args, &block|
        debug_state "run_with_child"
        if options[:master]
          GC.disable
          proxy = CodProxy.new(self) # reporter
          proxy_block = ->(reporter) do
            block.call(proxy)
          end
          Amnesia.run_iopipe if Spork.using_spork?
          #puts "***************** First fork *******************"
        else # If we're not in charge here, we need a token to run
          debug_state "waiting for token"
          Amnesia.wait(options[:example] ? 0 : 1) # Higher priority for examples than example groups
        end
        debug_state "parent starting child"
        Amnesia.in_child do
          begin
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