# Repository Guidelines

## Project Structure & Module Organization
- `lib/` contains the ClickhouseRuby client, type system, errors, and optional ActiveRecord integration.
- `spec/` contains unit and integration specs plus shared helpers under `spec/support/`.
- `docker/` and `docker-compose.yml` support local ClickHouse for integration testing.
- `README.md` and `CHANGELOG.md` document usage and changes.

Key modules to know:
- Client API: `lib/clickhouse_ruby/client.rb`
- Connection/pooling: `lib/clickhouse_ruby/connection.rb`, `lib/clickhouse_ruby/connection_pool.rb`
- Types: `lib/clickhouse_ruby/types/`
- ActiveRecord adapter: `lib/clickhouse_ruby/active_record/`

## Build, Test, and Development Commands
- `bundle exec rake spec` runs all tests (unit + integration if enabled).
- `bundle exec rake spec_unit` runs unit tests only (fast, no ClickHouse required).
- `CLICKHOUSE_TEST_INTEGRATION=true bundle exec rake spec_integration` runs integration tests.
- `bundle exec rspec spec/unit/clickhouse_ruby/client_spec.rb` runs a single file.
- `bundle exec rspec --example "handles connection errors"` runs matching examples.
- `bundle exec rake rubocop` checks style; `bundle exec rake rubocop_fix` auto-fixes.
- `bundle exec rake check` runs tests and linting.
- `docker-compose up -d` starts a local ClickHouse server.

## Coding Style & Naming Conventions
- Ruby files must include `# frozen_string_literal: true`.
- Line length: 120 characters max.
- Use double quotes for string literals.
- Use trailing commas in multiline arrays/hashes/arguments.
- RSpec context prefixes: `when`, `with`, `without`, `if`, `unless`, `for`, `given`.

## Testing Guidelines
- Framework: RSpec; HTTP is mocked with WebMock for unit tests.
- Integration tests require `CLICKHOUSE_TEST_INTEGRATION=true` and a running ClickHouse.
- Coverage target: 80% overall (see `coverage/`).
- Place shared helpers in `spec/support/`.

## Commit & Pull Request Guidelines
- No explicit commit message convention is documented; follow standard semantic, scoped messages if possible (e.g., `fix: handle timeout`).
- PRs should include a clear description, test results, and any relevant ClickHouse configuration notes.

## Architecture Overview
- Client API uses JSONCompact for queries and JSONEachRow for inserts, and checks HTTP status before parsing.
- Errors map ClickHouse codes to specific exception classes in `lib/clickhouse_ruby/errors.rb`.
