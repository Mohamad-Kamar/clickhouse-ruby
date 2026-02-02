# Contributing to ClickhouseRuby

Thank you for your interest in contributing to ClickhouseRuby! This guide will help you get started.

## Getting Started

### Prerequisites

- Ruby >= 2.6.0
- Docker (for integration tests)
- Bundler

### Setup

```bash
# Clone the repository
git clone https://github.com/Mohamad-Kamar/clickhouse-ruby.git
cd clickhouse-ruby

# Install dependencies
bundle install

# Start ClickHouse for integration tests
docker-compose up -d
```

## Development Workflow

### Running Tests

```bash
# Run all tests (unit + integration if enabled)
bundle exec rake spec

# Run unit tests only (fast, no ClickHouse required)
bundle exec rake spec_unit

# Run integration tests (requires ClickHouse)
CLICKHOUSE_TEST_INTEGRATION=true bundle exec rake spec_integration

# Run a single test file
bundle exec rspec spec/unit/clickhouse_ruby/client_spec.rb

# Run tests matching a pattern
bundle exec rspec --example "handles connection errors"
```

### Code Quality

```bash
# Check code style
bundle exec rake rubocop

# Auto-fix style issues
bundle exec rake rubocop_fix

# Run all checks (tests + linting)
bundle exec rake check
```

## Code Style

Please follow these conventions:

- **Frozen string literals**: All Ruby files must include `# frozen_string_literal: true`
- **Line length**: 120 characters maximum
- **String literals**: Use double quotes (`"string"`)
- **Trailing commas**: Required in multiline arrays, hashes, and arguments
- **RSpec context prefixes**: Use `when`, `with`, `without`, `if`, `unless`, `for`, `given`

## Project Structure

```
lib/
├── clickhouse_ruby/
│   ├── client.rb           # Main client API
│   ├── connection.rb       # HTTP connection handling
│   ├── connection_pool.rb  # Thread-safe connection pool
│   ├── configuration.rb    # Configuration management
│   ├── errors.rb           # Error hierarchy
│   ├── result.rb           # Query result handling
│   ├── types/              # Type system (parser, registry, individual types)
│   └── active_record/      # Optional ActiveRecord integration
spec/
├── unit/                   # Unit tests (mocked HTTP)
├── integration/            # Integration tests (real ClickHouse)
└── support/                # Shared test helpers
```

## Making Changes

### 1. Create a Branch

```bash
git checkout -b feature/my-new-feature
```

### 2. Make Your Changes

- Write tests for new functionality
- Ensure all tests pass: `bundle exec rake check`
- Follow the code style guidelines

### 3. Commit Your Changes

Use clear, descriptive commit messages:

```bash
git commit -m "feat: add support for new feature"
git commit -m "fix: handle edge case in type parser"
git commit -m "docs: update configuration guide"
```

### 4. Submit a Pull Request

- Push your branch: `git push origin feature/my-new-feature`
- Open a pull request on GitHub
- Include a clear description of your changes
- Reference any related issues

## Testing Guidelines

- **Unit tests**: Use WebMock to mock HTTP interactions
- **Integration tests**: Require a running ClickHouse instance
- **Coverage target**: Maintain 80%+ code coverage
- **Test helpers**: Place shared helpers in `spec/support/`

## Architecture Notes

Understanding the codebase:

- **Client API**: Uses JSONCompact for queries, JSONEachRow for inserts
- **Error handling**: Maps ClickHouse error codes to specific exception classes
- **Type system**: AST-based parser handles complex nested types
- **Connection pool**: Thread-safe with health checks before returning connections

## Getting Help

- Check existing [issues](https://github.com/Mohamad-Kamar/clickhouse-ruby/issues)
- Read the [documentation](docs/)
- Open a new issue for bugs or feature requests

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
