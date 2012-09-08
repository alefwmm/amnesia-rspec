module RSpec
  module Core
    module Hooks
      #class Hook
      #  def call
      #    puts "#{display_name} #{@block.inspect}"
      #    @block.call
      #  end
      #
      #  def to_proc
      #    puts "#{display_name} #{@block.inspect}"
      #    @block
      #  end
      #end

      # In the new fork order, there's no distinction between :each and :all
      def scope_and_options_from_with_no_each(*args)
        if args[0] == :really_each
          args[0] = :each
          scope_and_options_from_without_no_each(*args)
        else
          scope, options = scope_and_options_from_without_no_each(*args)
          if false && Amnesia::Config.enabled
            return scope == :each ? :all : scope, options
          else
            return scope, options
          end
        end
      end
      alias_method_chain :scope_and_options_from, :no_each
    end
  end
end
