module RSpec
  module Core
    module Hooks
      #class Hook
      #  include Amnesia::Logging
      #  def call
      #    debug "#{display_name} #{@block.inspect}"
      #    @block.call
      #  end
      #
      #  def to_proc
      #    debug "#{display_name} #{@block.inspect}"
      #    @block
      #  end
      #end

      # In the new fork order, there's no distinction between :each and :all
      def before(*args, &block)
        if args[0] == :really_each
          really_each = true
          args[0] = :each
        end
        scope, options = scope_and_options_from(*args)
        if scope == :each && !really_each && Amnesia::Config.enabled && Amnesia::Config.before_optimization && !metadata[:disable_before_optimization]
          hooks[:before][:all] << BeforeHook.new(options, &block)
        else
          hooks[:before][scope] << BeforeHook.new(options, &block)
        end
      end
    end
  end
end
