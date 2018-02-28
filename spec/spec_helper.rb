if !defined?(Rails)
  module ::Rails
    def self.root
      File.expand_path('.')
    end

    def self.logger
      STDOUT
    end
  end
end

Bundler.require(:default, :development)

require 'active_record'
require 'background_job_tracking'

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

load './db/schema.rb'
