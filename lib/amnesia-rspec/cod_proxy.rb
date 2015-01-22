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
      # puts "Proxying: #{args[0]}"
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

# Define serialization format for Examples to only contain stuff we care about, and avoid trying
# to dump things like Procs that will raise exceptions
class RSpec::Core::Example
  def marshal_dump
    metadata = [:description, :full_description, :execution_result, :file_path, :pending, :location].each_with_object({}) do |k, h|
      h[k] = @metadata[k]
    end
    {
        # Only stuff we really want
        # Have to actually call [] for each key on @metadata, it's not a normal hash we can #slice
        metadata: metadata,

        # Necessary to avoid Proc serialization error in @assigns ivar of AV::T::E; also seems more helpful
        exception: @exception.is_a?(ActionView::Template::Error) ? @exception.original_exception : @exception,

        example_group: example_group.to_s # Can't dump class
    } #.tap {|data| puts "Marshalled Example to: #{data.inspect}"}
  end

  def marshal_load(data)
    @example_group_class = data.delete(:example_group).constantize if data[:example_group]
    # puts "Loading keys: #{data.keys}"
    # puts "Loading values: #{data.values}"
    data.each_pair do |k, v|
      # puts "Loading k: #{k}"
      # puts "Loading v: #{v}"
      begin
        instance_variable_set("@#{k}", v)
      rescue NameError
        puts "WTF? Disallowed instance variable name in serialized Example: #{k}"
        puts "Full data: #{data.inspect}"
      end
    end
  end
end