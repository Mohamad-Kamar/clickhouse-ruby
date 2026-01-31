# frozen_string_literal: true

require_relative "lib/clickhouse_ruby/version"

Gem::Specification.new do |spec|
  spec.name = "clickhouse-ruby"
  spec.version = ClickhouseRuby::VERSION
  spec.authors = ["Mohamad Kamar"]
  spec.email = ["mohamad.kamar.dev@gmail.com"]

  spec.summary = "Ruby/ActiveRecord integration for ClickHouse"
  spec.description = "A lightweight Ruby client for ClickHouse with optional ActiveRecord integration. " \
                     "Provides a simple interface for querying, inserting, and managing ClickHouse databases."
  spec.homepage = "https://github.com/kamardev/clickhouse-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/kamardev/clickhouse-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/kamardev/clickhouse-ruby/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/clickhouse-ruby"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir["lib/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = []
  spec.require_paths = ["lib"]

  # Runtime dependencies - minimal, using standard library only
  # net-http and json are part of Ruby standard library

  # Development dependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "simplecov", "~> 0.21.0"  # Ruby 2.6 compatible
  spec.add_development_dependency "webmock", "~> 3.18.0"  # Ruby 2.6 compatible
  spec.add_development_dependency "yard", "~> 0.9"

  # Optional: uncomment for linting (requires Ruby 2.7+)
  # spec.add_development_dependency "rubocop", "~> 1.60"
  # spec.add_development_dependency "rubocop-rspec", "~> 2.26"
  # spec.add_development_dependency "vcr", "~> 6.2"
end
