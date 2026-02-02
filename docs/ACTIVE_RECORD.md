# ActiveRecord Support

## Overview
ClickhouseRuby ships an optional ActiveRecord adapter. It registers the `clickhouse` adapter and maps common ActiveRecord APIs to ClickHouse SQL, with explicit error handling (no silent failures).

## Setup
Require the adapter and configure a ClickHouse connection. In Rails, add a `database.yml` entry; outside Rails, use `ActiveRecord::Base.establish_connection`.

```yaml
# config/database.yml
clickhouse:
  adapter: clickhouse
  host: localhost
  port: 8123
  database: analytics
  username: default
  password: ""
  ssl: false
  ssl_verify: true
  ssl_ca_path: "/path/to/ca.pem"
  pool: 5
  connect_timeout: 10
  read_timeout: 60
  write_timeout: 60
```

```ruby
# config/initializers/clickhouse.rb
require "clickhouse_ruby/active_record"

class ClickhouseRecord < ActiveRecord::Base
  self.abstract_class = true
  establish_connection :clickhouse
end
```

## Models and Queries
```ruby
class Event < ClickhouseRecord
  self.table_name = "events"
end

Event.where(event_type: "click").order(created_at: :desc).limit(10)
Event.insert_all([{ id: SecureRandom.uuid, event_type: "click" }])
Event.where(user_id: 123).update_all(status: "archived")
Event.where(status: "old").delete_all
```

Notes:
- `update_all` / `delete_all` are translated to `ALTER TABLE ... UPDATE/DELETE`.
- Mutations are asynchronous in ClickHouse; the call returns once accepted.
- ClickHouse does not return insert IDs; `insert_all` is recommended for bulk writes.

## Schema and Migrations
The adapter implements `create_table`, `add_column`, `change_column`, `rename_column`, `add_index`, and related schema helpers. MergeTree tables require an engine and an `ORDER BY`.

```ruby
class CreateEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :events, engine: "MergeTree", order_by: "(event_type, created_at)",
                          partition_by: "toYYYYMM(created_at)" do |t|
      t.uuid :id, null: false
      t.string :event_type, null: false
      t.datetime :created_at, null: false
    end

    add_index :events, :event_type, type: "set", granularity: 1
  end
end
```

## Type Mapping
Common mappings: `string/text -> String`, `integer -> Int32`, `bigint -> Int64`, `float -> Float32/64`,
`decimal -> Decimal(p,s)`, `datetime/timestamp -> DateTime/DateTime64`, `date -> Date`, `uuid -> UUID`,
`json -> String`. `Array`, `Map`, and `Tuple` columns are treated as strings in ActiveRecord type casting.

## Limitations
- No transactions, savepoints, or rollback.
- No foreign keys, check constraints, insert returning, comments, partial/expression indexes, or standard views.
- No auto-increment primary keys; generate IDs in your application.

## Rails Database Tasks
When used in Rails, the adapter plugs into `db:create`, `db:drop`, and `db:purge`. It also supports
structure dump/load via `db:structure:dump` and `db:structure:load` (ClickHouse `SHOW CREATE TABLE`).
