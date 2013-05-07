module Amnesia
  def self.stupid_cache_for_ar
    @stupid_cache_for_ar ||= {}
  end

  # We want to give the DB a second to settle before forking if we've been using it in the parent
  def self.accessed_db
    db_pid_list[Process.pid] = true
  end

  def self.settle_db
    if db_pid_list[Process.pid]
      debug "Allowing DB to settle"
      sleep 1
      db_pid_list[Process.pid] = false
    end
  end

  private
  def self.db_pid_list
    @db_pid_list ||= {}
  end
end

module ActiveRecord
  module ConnectionAdapters
    class Mysql2Adapter
      def create_table(table_name, options = {})
        super(table_name, options.reverse_merge(:options => "ENGINE=MEMORY"))
      end

      #Text type not supported by MEMORY engine
      def type_to_sql_with_notext(*args)
        type = type_to_sql_without_notext(*args)
        if type =~ /^(text|blob)/
          'varchar(2500)' # If this is bigger than about 21000 it always fails, and sometimes hits a row limit anyway if too large
        else
          type
        end
      end
      alias_method_chain :type_to_sql, :notext

      def execute_with_stupid_cache(sql, name = nil)
        Amnesia.accessed_db
        @stupid_cache ||= Amnesia.stupid_cache_for_ar
        return @stupid_cache[sql] if @stupid_cache[sql]
        attempts = 0
        begin
          attempts += 1
          result = execute_without_stupid_cache(sql, name)
        rescue => ex
          if ex.message =~ /\.MYI|Can't find file|File '.*' not found/
            puts "Evil disk access triggered by query: #{sql}"
            puts ex.message
            if attempts < 5
              sleep 0.1
              retry
            elsif attempts < 25
              # Try doing some other crap that we know uses tmpfiles to mess the state around; god this is a hack
              begin
                execute_without_stupid_cache(@stupid_cache.sample[0])
              rescue => ex
                puts ex.message
              end
              sleep 0.25
              retry
            else
              raise "Amnesia got MySQL stuck in a broken state, sorry. Query was: #{sql}"
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
      alias_method_chain :execute, :stupid_cache

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

