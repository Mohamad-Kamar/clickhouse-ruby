# frozen_string_literal: true

require 'simplecov'

SimpleCov.start do
  add_filter '/spec/'
  add_filter '/vendor/'

  add_group 'Types', 'lib/clickhouse_ruby/types'
  add_group 'Core', 'lib/clickhouse_ruby'
  add_group 'ActiveRecord', 'lib/clickhouse_ruby/active_record'

  minimum_coverage 80
  minimum_coverage_by_file 70
end

require 'bundler/setup'
require 'clickhouse_ruby'
require 'webmock/rspec'

# Load support files
Dir[File.join(__dir__, 'support', '**', '*.rb')].sort.each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Run specs in random order to surface order dependencies
  config.order = :random
  Kernel.srand config.seed

  # Filter integration tests by default (run with --tag integration)
  config.filter_run_excluding integration: true unless ENV['CLICKHOUSE_TEST_INTEGRATION']

  # Reset ClickhouseRuby configuration before each test
  config.before(:each) do
    ClickhouseRuby.reset_configuration!
    ClickhouseRuby::Types.reset!
  end

  # Integration test setup
  config.before(:suite) do
    if ENV['CLICKHOUSE_TEST_INTEGRATION']
      ClickhouseHelper.setup_test_database
    end
  end

  config.after(:suite) do
    if ENV['CLICKHOUSE_TEST_INTEGRATION']
      ClickhouseHelper.teardown_test_database
    end
  end

  # Tag slow tests
  config.around(:each, :slow) do |example|
    Timeout.timeout(30) { example.run }
  end
end

# Custom matchers
RSpec::Matchers.define :be_a_clickhouse_error do |expected_class|
  match do |actual|
    actual.is_a?(expected_class) || actual.is_a?(ClickhouseRuby::Error)
  end

  failure_message do |actual|
    "expected #{actual.inspect} to be a ClickHouse error (#{expected_class})"
  end
end

RSpec::Matchers.define :have_error_code do |expected_code|
  match do |actual|
    actual.respond_to?(:code) && actual.code == expected_code
  end

  failure_message do |actual|
    "expected #{actual.inspect} to have error code #{expected_code}, got #{actual.code rescue 'N/A'}"
  end
end
