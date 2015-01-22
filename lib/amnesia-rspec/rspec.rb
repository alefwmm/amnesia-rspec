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

          # Avoid overwriting the @request from a before_each that was optimized into a before_all
          if respond_to?(:setup_controller_request_and_response)
            class << self
              def setup_controller_request_and_response_with_check_first
                unless @request && @response
                  setup_controller_request_and_response_without_check_first
                end
              end
              alias_method_chain :setup_controller_request_and_response, :check_first
            end
          end

          # Same thing with @rendered, for view tests
          if respond_to?(:setup_with_controller)
            class << self
              def setup_with_controller_with_check_first
                unless @request && @rendered
                  setup_with_controller_without_check_first
                end
              end
              alias_method_chain :setup_with_controller, :check_first
            end
          end
        end
      end

      # Provide access to filters on example_group_instance for before_each hooks which are expecting Example instance
      def all_apply?(filters)
        self.class.all_apply?(filters)
      end

      class << self
        extend Amnesia::RunWithFork
        run_with_fork timeout: Amnesia::Config.example_group_timeout

        def run_before_all_hooks_with_mocks(example_group_instance)
          #puts "[#{Process.pid}] #{self} before_all_hooks start"

          if Amnesia::Config.before_optimization && !example_group_instance.class.metadata[:disable_before_optimization]
            # Normally happens in example#run_before_each, but need it here for each->all converted blocks
            example_group_instance.setup_mocks_for_rspec

            # really_each blocks should always be set up at every nesting level to allow before each stuff to work
            run_before_each_hooks(example_group_instance)
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
      run_with_fork example: true, timeout: Amnesia::Config.example_timeout

      # Don't need to do after stuff aside from verifying mocks, will exit() shortly
      def run_after_each
        #puts "[#{Process.pid}] #{self} after_each"
        @example_group_instance.verify_mocks_for_rspec
        Amnesia.check_for_server_errors!
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
      # We need to separate the non-yielding part of report (that calls start), which needs to run in the parent,
      # from the yield of the block, which we want to happen in the child
      def report_with_run(expected_example_count, *args, &block)
        report_without_run(expected_example_count, *args) do
          @passed_count = 0
          run(&block)
          missing_count = expected_example_count - @passed_count - @pending_count - @failure_count
          if missing_count > 0
            begin
              raise "No report received for #{missing_count} examples, assuming they failed/crashed"
            rescue => ex
              example_failed(Example.new(
                                 ExampleGroup.describe(""),
                                 ex.message,
                                 {execution_result: {exception: ex}} # This makes instafail happy
                             ))
            end
          end
          # It seems like this might result in proper return code, except that exit codes appear to be broken in the
          # version of RSpec I'm testing with regardless; so no idea if this has any effect
          #@failure_count == 0 ? 0 : RSpec::configuration.failure_exit_code
          # Nevermind, force the issue
          Amnesia.exit_status = @failure_count
        end
      end
      alias_method_chain :report, :run

      def example_passed_with_count(example)
        @passed_count += 1
        example_passed_without_count(example)
      end
      alias_method_chain :example_passed, :count

      def run
        yield self
      end

      extend Amnesia::RunWithFork
      run_with_fork master: true, timeout: Amnesia::Config.master_timeout
    end
  end
end

