require 'cod'
require 'oj'

module Cod
  class OjSerializer
    include Amnesia::Logging

    OPTIONS = {
        indent: 0,
        circular: false,
        auto_define: false,
        symbol_keys: true,
        escape_mode: nil,
        class_cache: true,
        mode: :object,
        create_id: nil,
        use_to_json: false,
        quirks_mode: true,
        nilnil: false
    }

    def en(obj)
      Oj.dump(obj, OPTIONS)
    end

    def de(io)
      Oj.load(io.gets, OPTIONS)
    end
  end
end

module Amnesia
  class CodProxy
    include Logging

    def initialize(target)
      debug "Building proxy for #{target.inspect}"
      @target = target
      @pipe = ::Cod::Pipe.new(Cod::OjSerializer.new, ::IO.pipe("binary"))
      @pipe.instance_eval do
        class << @pipe # The Cod::IOPair instance for this Cod::Pipe
          include Amnesia::Logging

          def write(buf)
            debug "requesting write for: #{buf}" if Config.debug
            Amnesia.safe_write do
              debug "executing write"

              # force_encoding should be unneccessary because the pipe should be binary, but Rails is screwing it
              # up somehow (works fine under straight ruby console)
              super(buf.force_encoding("UTF-8") + "\n") # Need newline to turn JSON stream into distinct messages

              debug "done write"
            end
            debug "released write"
          end
        end
      end
    end

    def method_missing(*args)
      # Proxying things that we don't really care about slows us down; also, screws up Teamcity which is expecting 1 thread
      return if [:example_group_started, :example_group_finished].include?(args[0])
      # puts "Proxying: #{args[0]}"
      begin
        args.map! do |obj|
          if obj.is_a? ::RSpec::Core::Example
            # Only stuff we really want
            # Have to actually call [] for each key on @metadata, it's not a normal hash we can #slice
            metadata = [:description, :full_description, :execution_result, :file_path, :pending, :location].each_with_object({}) do |k, h|
              h[k] = obj.metadata[k]
            end
            dummy_example = ::RSpec::Core::Example.allocate
            dummy_example.instance_variable_set('@metadata', metadata)
            %w[exception example_group_class].each do |var|
              var = "@#{var}"
              dummy_example.instance_variable_set(var, obj.instance_variable_get(var))
            end

            dummy_example
          else
            obj
          end
        end

        @pipe.put(args)

      rescue Exception => ex
        puts "[#{Process.pid}] " + ex.message
        puts "[#{Process.pid}] Amnesia could not report example result: " + args.inspect
      end
    end

    def run_proxy_to_end
      begin
        while true do
          args = @pipe.get
          debug "Got: " + args.inspect if Amnesia::Config.debug
          @target.send(*args)
        end
      rescue ::Cod::ConnectionLost
      end
    end
  end
end

