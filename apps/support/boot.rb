# Shared boot for the single-file lab apps. Booting a minimal Rails app runs
# the funes engine initializers, which register the engine's app/ directories
# (Funes::Event and friends) for autoloading. It also connects Active Record
# to an in-memory SQLite database and installs the funes schema, so each app
# only defines its own tables, code, and tests.
require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "minitest/autorun"
require "minitest/spec"
require_relative "funes_schema"

ENV["DATABASE_URL"] ||= "sqlite3::memory:"

class LabApp < Rails::Application
  config.load_defaults Rails::VERSION::STRING.to_f
  config.eager_load = false
  config.logger = Logger.new(nil)
  config.secret_key_base = "lab"
end

Rails.application.initialize!

ActiveRecord::Schema.verbose = false
ActiveRecord::Migration.verbose = false

FunesSchema.migrate!
