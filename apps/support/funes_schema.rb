# Runs the migrations that `rails generate funes:install` produces, against the
# current Active Record connection. Generating into a throwaway directory keeps
# the apps in sync with whatever schema the installed funes-rails version ships.
require "rails/generators"
require "funes"
require "tmpdir"

module FunesSchema
  def self.migrate!
    Dir.mktmpdir do |dir|
      Rails::Generators.invoke("funes:install", [ "--quiet" ], destination_root: dir)
      ActiveRecord::MigrationContext.new([ File.join(dir, "db/migrate") ]).migrate
    end
  end
end
