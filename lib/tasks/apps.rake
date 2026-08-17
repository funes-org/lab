desc "Run every app's checks, each in its own process"
task :apps do
  files = Dir[File.expand_path("../../apps/*/app.rb", __dir__)].sort
  abort "No apps found" if files.empty?

  failed = files.reject { |file| system(RbConfig.ruby, file) }
  abort "#{failed.size} app(s) failed:\n#{failed.join("\n")}" if failed.any?

  puts "#{files.size} apps passed"
end