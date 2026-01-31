-- Create test database for integration tests
CREATE DATABASE IF NOT EXISTS chruby_test;

-- Create sample events table for testing
CREATE TABLE IF NOT EXISTS chruby_test.events (
    id UUID DEFAULT generateUUIDv4(),
    date Date,
    event_type String,
    user_id UInt64,
    properties String,
    count UInt32 DEFAULT 1,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (date, event_type, user_id);

-- Create sample users table for testing
CREATE TABLE IF NOT EXISTS chruby_test.users (
    id UInt64,
    name String,
    email String,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY id;

-- Insert sample data
INSERT INTO chruby_test.events (date, event_type, user_id, properties, count) VALUES
    ('2024-01-01', 'page_view', 1, '{"page": "/home"}', 10),
    ('2024-01-01', 'click', 1, '{"button": "signup"}', 2),
    ('2024-01-02', 'page_view', 2, '{"page": "/pricing"}', 5),
    ('2024-01-02', 'purchase', 2, '{"amount": 99.99}', 1);

INSERT INTO chruby_test.users (id, name, email) VALUES
    (1, 'Alice', 'alice@example.com'),
    (2, 'Bob', 'bob@example.com');
