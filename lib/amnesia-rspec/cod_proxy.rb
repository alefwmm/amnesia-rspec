require 'cod'

module Amnesia
  class CodProxy
    def initialize(target)
      #puts "[#{Process.pid}] Building proxy for #{target.inspect}"
      @target = target
      @pipe = ::Cod::Pipe.new(nil, ::IO.pipe("binary"))
      @pipe.instance_eval do
        class << @pipe # The Cod::IOPair instance for this Cod::Pipe
          def write(buf)
            #puts "[#{::Process.pid}] requesting write"
            Amnesia.safe_write do
              #puts "[#{::Process.pid}] executing write"

              # force_encoding should be unneccessary because the pipe should be binary, but Rails is screwing it
              # up somehow (works fine under straight ruby console)
              super(buf.force_encoding("UTF-8"))

              #puts "[#{::Process.pid}] done write"
            end
            #puts "[#{::Process.pid}] released write"
          end
        end
      end
    end

    def method_missing(*args)
      # Proxying things that we don't really care about slows us down; also, screws up Teamcity which is expecting 1 thread
      return if [:example_group_started, :example_group_finished].include?(args[0])
      #puts "Proxying: #{args[0]}"
      args.map! do |obj|
        if obj.is_a? ::RSpec::Core::Example
          obj.dup.tap do |example|
            example.instance_eval do
              # Get rid of junk we can't or don't want to serialize
              @example_block = @example_group_instance = @around_hooks = nil
              # Do it this way to trigger lazy generation
              @metadata = [:description, :full_description, :execution_result, :file_path, :pending, :location].each_with_object({}) do |k, h|
                h[k] = @metadata[k]
              end
            end
          end
        else
          obj
        end
      end
      begin
        @pipe.put(args)
      rescue => ex
        puts "[#{Process.pid}] Error putting: " + args.inspect
        raise ex
      end
    end

    def run_proxy_to_end
      begin
        while true do
          args = @pipe.get
          #puts "[#{Process.pid}] Got: " + args.inspect
          @target.send(*args)
        end
      rescue ::Cod::ConnectionLost
      end
    end
  end
end