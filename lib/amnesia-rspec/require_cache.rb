module Amnesia
  class RequireCache
    @filename = Config.require_cache

    def self.activate!
      load @filename if File.exists?(@filename)

      Kernel.class_eval do
        def load_with_noise(*args)
          load_without_noise(*args).tap do |result|
            puts "Load, not adding to cache: " + args.inspect
          end
        end
        alias_method_chain :load, :noise
        def require_with_noise(*args)
          require_without_noise(*args).tap do |result|
            if result
              puts "Require, adding to cache: " + args.inspect
              RequireCache.add(*args)
            end
          end
        end
        alias_method_chain :require, :noise
      end
    end

    def self.add(file)
      loaded_from = $LOAD_PATH.find {|p| file.include?(p)}
      if loaded_from
        file.slice!(loaded_from + '/') # Reduce to relative path
      end
      str = "require '#{file}'"
      File.open(@filename, 'a+') do |f|
        f.flock(File::LOCK_EX)
          unless f.read.include?(str)
            f.puts str
          end
        f.flock(File::LOCK_UN)
      end
    end
  end
end
