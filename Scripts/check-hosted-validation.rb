#!/usr/bin/env ruby
# Keep simulator compilation and execution in local validation, never hosted CI.
require "yaml"

root = File.expand_path("..", __dir__)
workflow_paths = Dir[File.join(root, ".github/workflows/*.{yml,yaml}")].sort
expected_path = File.join(root, ".github/workflows/ci.yml")
abort("Review new hosted workflows against the local-only simulator policy") unless workflow_paths == [expected_path]

jobs = YAML.load_file(expected_path).fetch("jobs")
expected_names = {
  "changes" => "Validation Scope", "lint" => "Lint", "docs" => "Docs and Config",
  "build" => "Build macOS", "test" => "Test macOS"
}
abort("Hosted validation must contain only the five approved checks") unless jobs.keys.sort == expected_names.keys.sort

jobs.each do |id, job|
  abort("Unexpected hosted job name: #{id}") unless job.fetch("name") == expected_names.fetch(id)
  abort("Hosted platform matrices are prohibited: #{id}") if job.key?("strategy")
  commands = job.fetch("steps").filter_map { |step| step["run"] }.join("\n")
  if commands.gsub("--waive-ci-simulator-discovery", "").match?(/simctl|simulator|validate-release\.py|screenshots\.sh/i)
    abort("Hosted simulator work is prohibited: #{id}")
  end
  commands.lines.grep(/\bxcodebuild\b/).each do |command|
    next if command.include?("xcodebuild -version") || command.include?("-resolvePackageDependencies")
    unless %w[build test].include?(id) && command.include?("-destination 'platform=macOS,arch=arm64'")
      abort("Hosted Xcode actions require an explicit native Apple Silicon Mac destination: #{id}")
    end
  end
end

%w[build test].each do |id|
  job = jobs.fetch(id)
  abort("Native jobs must honor cancellation") unless job.fetch("if") == "${{ !cancelled() }}"
  abort("Native jobs must require change classification") unless job.fetch("needs") == "changes"
end

puts "Hosted validation policy passed: five checks; native macOS only."
