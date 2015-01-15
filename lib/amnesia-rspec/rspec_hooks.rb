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
      def before_with_amnesia(*args, &block)
        if args[0] == :really_each
          really_each = true
          args[0] = :each
        end
        if !really_each && Amnesia::Config.enabled && Amnesia::Config.before_optimization && !metadata[:disable_before_optimization]
          # We weren't told not to do conversion by anything; check if it's an :each, and if so, convert it to an :all
          if args[0] == :each
            args[0] = :all
          elsif !args[0].is_a? Symbol # :each by default
            args.unshift(:all)
          else # wasn't an :each to begin with, leave it alone
          end
        end
        before_without_amnesia(*args, &block)
      end
      alias_method_chain :before, :amnesia

    end
  end
end
