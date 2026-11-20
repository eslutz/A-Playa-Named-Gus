#!/usr/bin/env ruby
# Keep app tests and simulator builds in local validation.
require "yaml"

root = File.expand_path("..", __dir__)
workflow_paths = Dir[File.join(root, ".github/workflows/*.{yml,yaml}")].sort
expected_path = File.join(root, ".github/workflows/ci.yml")
abort("Review new hosted workflows against the local test policy") unless workflow_paths == [expected_path]

jobs = YAML.load_file(expected_path).fetch("jobs")
expected_names = {
  "changes" => "Validation Scope", "lint" => "Lint", "docs" => "Docs and Config",
  "build" => "Build macOS"
}
abort("Hosted validation must contain only the four approved checks") unless jobs.keys.sort == expected_names.keys.sort

jobs.each do |id, job|
  abort("Unexpected hosted job name: #{id}") unless job.fetch("name") == expected_names.fetch(id)
  abort("Hosted platform matrices are prohibited: #{id}") if job.key?("strategy")
  commands = job.fetch("steps").filter_map { |step| step["run"] }.join("\n")
  if commands.gsub("--waive-ci-simulator-discovery", "").match?(/simctl|simulator|validate-release\.py|screenshots\.sh/i)
    abort("Hosted simulator work is prohibited: #{id}")
  end
  commands.lines.grep(/\bxcodebuild\b/).each do |command|
    if command.match?(/\b(?:test|test-without-building|build-for-testing)\b/i)
      abort("Hosted Xcode test actions are prohibited: #{id}")
    end
    next if command.include?("xcodebuild -version") || command.include?("-resolvePackageDependencies")
    unless id == "build" && command.include?("-destination 'platform=macOS,arch=arm64'") &&
           command.strip.end_with?(" build")
      abort("Hosted Xcode actions may only build for native Apple Silicon macOS: #{id}")
    end
  end
end

build = jobs.fetch("build")
abort("Native build must honor cancellation") unless build.fetch("if") == "${{ !cancelled() }}"
abort("Native build must require change classification") unless build.fetch("needs") == "changes"

puts "Hosted validation policy passed (four checks, native macOS build only)."
