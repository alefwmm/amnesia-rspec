# Installation

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

Now if I haven't forgetten anything (unlikely) and your environment is in every way compatible (also unlikely), you could magically run:

    AMNESIA=5 bundle exec rspec spec

Let me know what breaks!

# Known Limitations

## Due to the MySQL Memory Engine

Text and blob columns aren't supported; they will be automatically converted to varchar by Amnesia, but if you have too many in one table, you may hit row size limit issues and need to tune the varchar size.

Transactions aren't supported; asking for them won't cause an error, but rollback will have no effect.

Unlike normal with MySQL, result row ordering will be unpredictable if you don't specify any ORDER BY. Probably you'll need to add ".order(:id)" to a whole bunch of places [that it arguably should have been anyway].

## Due to before(:each) optimization (if enabled)

When using an external driver (capybara-webkit), whatever web page the browser is on at the end of the before block(s) will be reloaded afresh at the beginning of the example -- so for instance if you fill in a form in the before block, then press submit in the example, that won't work. If you need to do something like that, set disable_before_optimization: true on that rspec context. 

If you modify an example instance variable inside a block defined in a before block but run during the example (e.g. in a stub return block), it won't work as expected.

Using 'def' to define an example-scoped method inside a before block won't work properly. Although why you'd do that is a mystery.

