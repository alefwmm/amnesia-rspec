require 'securerandom'

module Amnesia
  def self.stupid_cache_for_ar
    @stupid_cache_for_ar ||= {}
  end

  # We want to give the DB a second to settle before forking if we've been using it in the parent
  def self.accessed_db
    db_pid_list[Process.pid] = true
  end

  def self.settle_db
    # Not clear this does anything
    #if db_pid_list[Process.pid]
    #  debug "Allowing DB to settle"
    #  sleep 1
    #  db_pid_list[Process.pid] = false
    #end
  end

  private
  def self.db_pid_list
    @db_pid_list ||= {}
  end
end

module ActiveRecord
  module ConnectionAdapters
    module SchemaStatements
      # No point in setting up indexes that don't change behavior; we're not going to have a ton of objects, and it slows down startup
      def add_index_with_or_not(table_name, column_name, options = {})
        if options[:unique]
          add_index_without_or_not(table_name, column_name, options)
        end
      end
      alias_method_chain :add_index, :or_not
    end

    class Mysql2Adapter
      # We can only have one client in the process when using embedded server
      def self.new(*args)
        @global_mysql2_adapter ||= super
      end

      def create_table(table_name, options = {})
        super(table_name, options.reverse_merge(:options => "ENGINE=MEMORY"))
      end

      #Text type not supported by MEMORY engine
      def type_to_sql_with_notext(*args)
        type = type_to_sql_without_notext(*args)
        if type =~ /(text|blob)/
          'varchar(2500)' # If this is bigger than about 21000 it always fails, and sometimes hits a row limit anyway if too large
        else
          type
        end
      end
      alias_method_chain :type_to_sql, :notext

      def thread_init_and_lock
        Thread.exclusive do
          @seen_threads ||= {}
          unless @seen_threads[Thread.current]
            @seen_threads[Thread.current] = true
            new_thread = true
          end
          #puts "#{@connection.inspect} #{Process.pid} #{Thread.current.inspect} #{new_thread.inspect}"
          @connection.init_thread if new_thread
          yield
        end
      end

      def execute_with_amnesia(*args)
        thread_init_and_lock { execute_with_stupid_cache(:execute, *args) }
      end
      alias_method_chain :execute, :amnesia

      def exec_query_with_amnesia(*args)
        thread_init_and_lock { execute_with_stupid_cache(:exec_query, *args) }
      end
      alias_method_chain :exec_query, :amnesia

      # execute and exec_query have slightly different args; method chaining above tells us which one to call
      def execute_with_stupid_cache(execute_method, sql, *args)
        Amnesia.accessed_db
        @stupid_cache ||= Amnesia.stupid_cache_for_ar
        return @stupid_cache[sql] if @stupid_cache[sql]
        attempts = 0
        begin
          attempts += 1
          result = send(:"#{execute_method}_without_amnesia", sql, *args)
        rescue => ex
          if ex.message =~ /\.MYI|Can't find file|File '.*' not found/
            puts "[#{Process.pid}] Evil disk access triggered in #{execute_method} by query: #{sql}"
            puts "[#{Process.pid}] #{ex.message}"
            if attempts < 100
              time = SecureRandom.random_number # Avoid predictable random seeding from tests
              puts "[#{Process.pid}] Sleeping for #{time}"
              sleep time # Try to desynchronize competing children starting at the same filename sequence position
              retry
            #elsif attempts < 25
            #  # Try doing some other crap that we know uses tmpfiles to mess the state around; god this is a hack
            #  begin
            #    execute_without_stupid_cache(@stupid_cache.to_a.sample[0])
            #  rescue => ex
            #    puts ex.message
            #  end
            #  sleep 0.25
            #  retry
            else
              #puts execute_without_stupid_cache("EXPLAIN #{sql}").inspect
              raise "[#{Process.pid}] Amnesia got MySQL stuck in a broken state, sorry. Query was: #{sql}"
            end
          else
            raise ex
          end
        end
        #tmpfiles = @connection.query("show global status like '%_tmp_%';").map {|r| r.inspect}[0..1].join("\n")
        #if tmpfiles != @tmpfiles
        #  @tmpfiles = tmpfiles
        #  puts sql
        #  puts @tmpfiles
        #  #begin
        #  #  raise "foo"
        #  #rescue => ex
        #  #  puts ex.backtrace.join("\n\t")
        #  #end
        #end
        result
      end

      def cache_schema_info!
        @stupid_cache ||= Amnesia.stupid_cache_for_ar
        execute("SHOW TABLES").each do |table|
          ['SHOW FIELDS FROM', 'describe'].each do |query|
            query += " `#{table[0]}`"
            @stupid_cache[query] = execute(query)
          end
        end
      end
    end
  end
end

