## Installation

These examples assume using the AMNESIA environment variable to activate Amnesia and set the number of parallel tests to run. That's not required, but is the easiest way we've figure out so far.

In your Gemfile:

    gem 'mysql2', '0.2.11', :group => ENV['AMNESIA'] && :disabled
    gem 'mysql2-amnesia', :git => 'git://github.com/chriswfx/mysql2', :branch => 'amnesia', :group => ENV['AMNESIA'] ? :default : :disabled
    
    group :test do
      gem 'amnesia-rspec', :git => 'git://github.com/chriswfx/amnesia-rspec'
    end

What's going on there is that you need to load an alternate MySQL driver when running in Amnesia mode, to get the in-process embedded MySQL server. This also means you want to configure bundle to exclude the :disabled group by default:

    $ cat .bundle/config 
    ---
    BUNDLE_WITHOUT: disabled

Next, you need to configure Amnesia in your spec_helper.rb; if using Spork, this goes in the prefork block:

    if ENV['AMNESIA']
      Amnesia.forkit_and_forget! do |config|
        config.max_workers = ENV['AMNESIA'].to_i
        config.before_optimization = true
        config.debug = false
        config.debug_server = false
        config.require_cache = '.amnesia_require_cache'
      end
    end

### First run

To prime your Amnesia bundle and databases, you'll need to prep each installation with:

    AMNESIA=1 bundle install
    AMNESIA=1 bundle exec rake RAILS_ENV=test db:create
    AMNESIA=1 bundle exec rake RAILS_ENV=test db:schema:load

### Running tests

Now to run tests:

    AMNESIA=5 bundle exec rspec spec

The number (5) is how many parallel tasks to run; usually you want this to be in the neighborhood of the number of processor cores on your machine.

Note that you want to run the tests with the rspec executable, NOT with 'rake spec', which will get confused by the Amnesia DB environment.

## Known Limitations

### Due to the MySQL Memory Engine

Text and blob columns aren't supported; they will be automatically converted to varchar by Amnesia, but if you have too many in one table, you may hit row size limit issues and need to tune the varchar size.

Transactions aren't supported; asking for them won't cause an error, but rollback will have no effect.

Unlike normal with MySQL, result row ordering will be unpredictable if you don't specify any ORDER BY. Probably you'll need to add ".order(:id)" to a whole bunch of places [that it arguably should have been anyway].

### Due to before(:each) optimization (if enabled)

When using an external driver (capybara-webkit), whatever web page the browser is on at the end of the before block(s) will be reloaded afresh at the beginning of the example -- so for instance if you fill in a form in the before block, then press submit in the example, that won't work. If you need to do something like that, set disable_before_optimization: true on that rspec context. 

If you modify an example instance variable inside a block defined in a before block but run during the example (e.g. in a stub return block), it won't work as expected.

Using 'def' to define an example-scoped method inside a before block won't work properly. Although why you'd do that is a mystery.

## Troubleshooting

### You get: No report received for X examples, assuming they failed/crashed

As it implies, this message means that a process that an example was running in failed to report back to the master process. This could be due to the ruby interpreter crashing. It could also be due to an exception being raised that couldn't be serialized, usually due to containing a Proc. In that case, you'll get output looking like this:

    [5835] Error putting: [:example_failed, #<RSpec::Core::Example:0x000000150ec698 @example_block=nil, @options={}, @example_group_class=RSpec::Core::ExampleGroup::Nested_348::Nested_1, @metadata={:description=>"should show feedback area if there exists a consult request", :full_description=>"diagnostic_reports/show.html.haml Feedback should show feedback area if there exists a consult request", :execution_result=>{:started_at=>2013-09-16 10:33:54 -0700, :exception=>#<NoMethodError: undefined method `impersonating?' for #<ActionView::TestCase::TestController:0x0000001172bb70>>, :status=>"failed", :finished_at=>2013-09-16 10:33:55 -0700, :run_time=>0.590576754}, :file_path=>"/home/teamcity/TeamCity/buildAgent.topaz-1/work/644541dc352cbb54/spec/views/diagnostic_reports/show.html.haml_spec.rb", :pending=>nil, :location=>"/home/teamcity/TeamCity/buildAgent.topaz-1/work/644541dc352cbb54/spec/views/diagnostic_reports/show.html.haml_spec.rb:42"}, @exception=#<NoMethodError: undefined method `impersonating?' for #<ActionView::TestCase::TestController:0x0000001172bb70>>, @pending_declared_in_example=false, @example_group_instance=nil, @around_hooks=nil>]
    #<TypeError: can't dump hash with default proc>
    	/home/teamcity/.rvm/gems/ruby-1.9.3-p448@topaz/gems/rspec-mocks-2.9.0/lib/rspec/mocks/extensions/marshal.rb:5:in `dump'
    	/home/teamcity/.rvm/gems/ruby-1.9.3-p448@topaz/gems/rspec-mocks-2.9.0/lib/rspec/mocks/extensions/marshal.rb:5:in `dump_with_mocks'
    	/home/teamcity/.rvm/gems/ruby-1.9.3-p448@topaz/gems/cod-0.5.0/lib/cod/simple_serializer.rb:15:in `en'
    	/home/teamcity/.rvm/gems/ruby-1.9.3-p448@topaz/gems/cod-0.5.0/lib/cod/pipe.rb:109:in `put'
    	/home/teamcity/.rvm/gems/ruby-1.9.3-p448@topaz/bundler/gems/amnesia-rspec-e2ec4a22b017/lib/amnesia-rspec/cod_proxy.rb:53:in `method_missing'
    	/home/teamcity/.rvm/gems/ruby-1.9.3-p448@topaz/gems/rspec-core-2.9.0/lib/rspec/core/example.rb:193:in `finish'

Amnesia attempts to nil out places known to be likely to contain Procs before serializing the test results. So if you get one of these, and can figure out where the Proc is, please report it as a bug. Otherwise, solving the underlying test failure will make this go away.

