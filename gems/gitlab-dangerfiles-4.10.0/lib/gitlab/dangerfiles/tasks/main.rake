# frozen_string_literal: true

desc "Run local Danger rules"
task :danger_local do
  require "open3"

  stdout, stderr, status = Open3.capture3({}, *%w{bundle exec danger dry_run})

  puts("#{stdout}#{stderr}")

  exit(status.exitstatus.to_i)
end
