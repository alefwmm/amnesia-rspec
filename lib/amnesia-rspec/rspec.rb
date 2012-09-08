module RSpec
  module Core
    ############### ALWAYS apply these patches ##############################
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

    ################### Only when using Amnesia mode below this line #################
    if Amnesia::Config.enabled
      class ExampleGroup
        class << self
          extend Amnesia::RunWithFork
          run_with_fork

          def run_before_all_hooks_with_mocks(example_group_instance)
            #puts "[#{Process.pid}] #{self} before_all_hooks start"
            example_group_instance.setup_mocks_for_rspec # Normally happens in example#run_before_each, but need it here for each->all converted blocks
            run_before_all_hooks_without_mocks(example_group_instance)
            #puts "[#{Process.pid}] #{self} before_all_hooks done"
          end
          alias_method_chain :run_before_all_hooks, :mocks

          # Skip it, gonna exit() momentarily
          def run_after_all_hooks(example_group_instance)
            #puts "[#{Process.pid}] #{self} after_all_hooks"
          end
        end
      end

      class Example
        extend Amnesia::RunWithFork
        run_with_fork counts_against_total: true

        # Don't need to do after stuff aside from verifying mocks, will exit() shortly
        def run_after_each
          #puts "[#{Process.pid}] #{self} after_each"
          @example_group_instance.verify_mocks_for_rspec
        end

        #require 'ruby-prof'
        #PROF_PATH = "#{File.expand_path('../../tmp', __FILE__)}/test_prof_#{Time.now.to_i}"
        #Dir.mkdir(PROF_PATH)
        #@@number = 0
        #@@number += 1
        #results = RubyProf.profile do
        #end
        #File.open File.join(PROF_PATH, @@number.to_s), 'w' do |file|
        #  RubyProf::CallTreePrinter.new(results).print(file)
        #end
      end

      class Reporter
        # We need to separate the non-yielding part of report (that calls start), which need to run in the parent,
        # from the yield of the block, which we want to happen in the child
        def report_with_run(*args, &block)
          report_without_run(*args) do
            run(&block)
          end
        end
        alias_method_chain :report, :run

        def run
          yield self
        end

        extend Amnesia::RunWithFork
        run_with_fork master: true
      end
    end
  end
end
