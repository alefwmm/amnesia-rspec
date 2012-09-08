module Amnesia
  module RunWithFork
    def run_with_fork(options = {})
      define_method :run_with_child do |*args, &block|
        puts "[#{Process.pid}] #{self} run_with_child" if Config.debug
        if options[:master]
          GC.disable
          proxy = CodProxy.new(self) # reporter
          proxy_block = ->(reporter) do
            block.call(proxy)
          end
          Amnesia.run_iopipe if Spork.using_spork?
          #puts "***************** First fork *******************"
        end
        if options[:counts_against_total]
          puts "[#{Process.pid}] #{self} waiting for signal" if Config.debug
          $0 = "ruby #{self} waiting for signal"
          Amnesia.wait
        end
        if child = Process.fork # Parent
          if proxy # Root level process receiving results
            Process.detach(child)
            puts "[#{Process.pid}] #{self} parent waiting for proxy" if Config.debug
            $0 = "ruby #{self} waiting for proxy"
            proxy.run_proxy_to_end
            Amnesia.cleanup
          elsif options[:counts_against_total]
            puts "[#{Process.pid}] #{self} parent setting child free" if Config.debug
            Process.detach(child)
            sleep 0.001 # If we exit immediately after detaching, seems to crash
          else
            puts "[#{Process.pid}] #{self} parent waiting for child" if Config.debug
            $0 = "ruby #{self} waiting for child"
            Process.wait(child)
          end
          puts "[#{Process.pid}] #{self} parent resuming" if Config.debug
          $0 = "ruby #{self} resumed"
        else # Child
          begin
            if Spork.using_spork?
              $stdout = STDOUT.reopen(Amnesia.output)
              $stderr = STDERR.reopen(Amnesia.output)
            end
            Amnesia.monitor_parent
            puts "[#{Process.pid}] #{self} child starting" if Config.debug
            $0 = "ruby #{self}"
            run_without_child(*args, &(proxy_block || block))
            puts "[#{Process.pid}] #{self} child finished" if Config.debug
          rescue => ex
            puts [ex.inspect, ex.backtrace].join("\n\t")
          ensure
            puts "[#{Process.pid}] #{self} child exiting" if Config.debug
            Amnesia.signal if options[:counts_against_total]
            exit!(true)
          end
        end
      end
      alias_method_chain :run, :child
    end
  end
end