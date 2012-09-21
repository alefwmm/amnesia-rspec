module RSpec
  module Core
    class ExampleGroup
      def initialize
        if Amnesia::Config.before_optimization
          # Provide a way for :each blocks to check out metadata as if in an example when running before(:all)
          klass = self.class
          @example = Object.new.tap do |obj|
            obj.define_singleton_method(:metadata) do
              klass.metadata
            end
            obj.define_singleton_method(:example_group) do
              klass
            end
          end

          # Setup up render notifications in case a new render happens in example, before ivars are populated with
          # previous results from earlier before blocks
          setup_subscriptions if respond_to?(:setup_subscriptions)
        end
      end

      class << self
        extend Amnesia::RunWithFork
        run_with_fork

        def run_before_all_hooks_with_mocks(example_group_instance)
          #puts "[#{Process.pid}] #{self} before_all_hooks start"

          if Amnesia::Config.before_optimization && !example_group_instance.class.metadata[:disable_before_optimization]
            # Normally happens in example#run_before_each, but need it here for each->all converted blocks
            example_group_instance.setup_mocks_for_rspec

            # really_each blocks should always be set up at every nesting level to allow before each stuff to work
            world.run_hook_filtered(:before, :each, self, example_group_instance)
          end

          run_before_all_hooks_without_mocks(example_group_instance)
          #puts "[#{Process.pid}] #{self} before_all_hooks done"
        end
        alias_method_chain :run_before_all_hooks, :mocks

        #def run_before_each_hooks_with_hacks(example)
        #  run_before_each_hooks_without_hacks(example)
        #end
        #alias_method_chain :run_before_each_hooks, :hacks

        # Skip it, gonna exit() momentarily
        def run_after_all_hooks(example_group_instance)
          # Prevent the line after the one that calls us from nuking stuff, because we need it during the goofy RWF work cycle for last-children
          before_all_ivars.define_singleton_method(:clear) {}
        end
      end
    end

    class Example
      extend Amnesia::RunWithFork
      run_with_fork example: true

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
