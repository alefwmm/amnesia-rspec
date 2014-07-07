module Amnesia
  class ConfiguredTimeout < StandardError; end

  module RunWithFork
    class << self
      include Logging

      def register_work(&block)
        raise "WTF" if @next_work
        @next_work = block
      end

      def perform_work(in_child)
        debug "performing work #{!!@next_work} (in_child = #{in_child})"
        return unless work = @next_work
        @next_work = nil
        if in_child
          debug_state "parent starting child"
          Amnesia.in_child do
            begin
              if Spork.using_spork?
                $stdout = STDOUT.reopen(Amnesia.output)
                $stderr = STDERR.reopen(Amnesia.output)
              end
              work.call
            rescue => ex
              puts [ex.inspect, ex.backtrace].join("\n\t")
            ensure
              RunWithFork.perform_work(false) # Finish the last bit of registered work in the child
              debug_state "child exiting"
              Amnesia.signal
              exit!(true)
            end
          end
        else
          begin
            work.call
          rescue => ex
            puts [ex.inspect, ex.backtrace].join("\n\t")
          ensure
            RunWithFork.perform_work(false) # Finish the last bit of registered work in the child
          end
        end
      end
    end

    def run_with_fork(options = {})
      include Amnesia::Logging

      define_method :run_with_child do |*args, &block|
        debug_state "run_with_child"
        # We've got more work to do, so fire off a child for any previous work
        RunWithFork.perform_work(true)
        
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
        debug "registering work for #{self}"
        RunWithFork.register_work do
          logging_with(self)
          debug_state "working"
          Timeout::timeout(options[:timeout], Amnesia::ConfiguredTimeout) do
            run_without_child(*args, &(proxy_block || block))
          end
        end
        # Parent
        if proxy # Root level process receiving results
          RunWithFork.perform_work(true) # Start the work we just registered in a child
          debug_state "parent waiting for proxy"
          proxy.run_proxy_to_end
          Amnesia.cleanup
        end
      end
      alias_method_chain :run, :child
    end
  end
end