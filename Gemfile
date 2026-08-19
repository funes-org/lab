source "https://rubygems.org"

# Provides Active Record and friends for the single-file apps
gem "rails", "~> 8.1.3"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects
  gem "bundler-audit", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

gem "funes-rails", "~> 0.3.0"
