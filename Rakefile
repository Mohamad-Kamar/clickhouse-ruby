# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = ["--format", "documentation"]
end

RSpec::Core::RakeTask.new(:spec_unit) do |t|
  t.rspec_opts = ["--format", "documentation", "--tag", "~integration"]
end

RSpec::Core::RakeTask.new(:spec_integration) do |t|
  t.rspec_opts = ["--format", "documentation", "--tag", "integration"]
end

RuboCop::RakeTask.new(:rubocop) do |t|
  t.options = ["--display-cop-names"]
end

RuboCop::RakeTask.new(:rubocop_fix) do |t|
  t.options = ["--autocorrect-all", "--display-cop-names"]
end

desc "Generate YARD documentation"
task :yard do
  require "yard"
  YARD::Rake::YardocTask.new do |t|
    t.files = ["lib/**/*.rb"]
    t.options = ["--output-dir", "doc", "--markup", "markdown"]
  end
end

desc "Run all checks (specs and rubocop)"
task check: %i[spec rubocop]

task default: :spec
