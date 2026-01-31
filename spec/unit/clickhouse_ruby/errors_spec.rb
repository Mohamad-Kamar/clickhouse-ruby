# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ClickhouseRuby::Errors' do
  describe ClickhouseRuby::Error do
    it 'is the base error class' do
      expect(described_class.superclass).to eq(StandardError)
    end

    it 'accepts a message' do
      error = described_class.new('Something went wrong')
      expect(error.message).to eq('Something went wrong')
    end

    it 'accepts an original_error' do
      original = StandardError.new('Original error')
      error = described_class.new('Wrapper error', original_error: original)
      expect(error.original_error).to eq(original)
    end

    it 'can be raised and caught' do
      expect { raise described_class, 'Test error' }.to raise_error(described_class)
    end
  end

  describe 'Connection errors' do
    describe ClickhouseRuby::ConnectionError do
      it 'inherits from ClickhouseRuby::Error' do
        expect(described_class.superclass).to eq(ClickhouseRuby::Error)
      end
    end

    describe ClickhouseRuby::ConnectionNotEstablished do
      it 'inherits from ConnectionError' do
        expect(described_class.superclass).to eq(ClickhouseRuby::ConnectionError)
      end

      it 'can be caught as ConnectionError' do
        expect { raise described_class, 'Connection refused' }.to raise_error(ClickhouseRuby::ConnectionError)
      end
    end

    describe ClickhouseRuby::ConnectionTimeout do
      it 'inherits from ConnectionError' do
        expect(described_class.superclass).to eq(ClickhouseRuby::ConnectionError)
      end
    end

    describe ClickhouseRuby::SSLError do
      it 'inherits from ConnectionError' do
        expect(described_class.superclass).to eq(ClickhouseRuby::ConnectionError)
      end
    end
  end

  describe 'Query errors' do
    describe ClickhouseRuby::QueryError do
      it 'inherits from ClickhouseRuby::Error' do
        expect(described_class.superclass).to eq(ClickhouseRuby::Error)
      end

      it 'accepts error code' do
        error = described_class.new('Query failed', code: 60)
        expect(error.code).to eq(60)
      end

      it 'accepts HTTP status' do
        error = described_class.new('Query failed', http_status: '500')
        expect(error.http_status).to eq('500')
      end

      it 'accepts SQL' do
        error = described_class.new('Query failed', sql: 'SELECT * FROM nonexistent')
        expect(error.sql).to eq('SELECT * FROM nonexistent')
      end

      it 'accepts all parameters' do
        error = described_class.new(
          'Query failed',
          code: 60,
          http_status: '500',
          sql: 'SELECT 1',
          original_error: StandardError.new('HTTP error')
        )

        expect(error.code).to eq(60)
        expect(error.http_status).to eq('500')
        expect(error.sql).to eq('SELECT 1')
        expect(error.original_error).to be_a(StandardError)
      end

      describe '#detailed_message' do
        it 'includes all context' do
          error = described_class.new(
            'Table not found',
            code: 60,
            http_status: '404',
            sql: 'SELECT * FROM missing_table'
          )

          detailed = error.detailed_message

          expect(detailed).to include('Table not found')
          expect(detailed).to include('Code: 60')
          expect(detailed).to include('HTTP Status: 404')
          expect(detailed).to include('SQL: SELECT * FROM missing_table')
        end

        it 'excludes nil values' do
          error = described_class.new('Simple error')
          detailed = error.detailed_message

          expect(detailed).to eq('Simple error')
          expect(detailed).not_to include('Code:')
          expect(detailed).not_to include('HTTP Status:')
          expect(detailed).not_to include('SQL:')
        end
      end
    end

    describe ClickhouseRuby::SyntaxError do
      it 'inherits from QueryError' do
        expect(described_class.superclass).to eq(ClickhouseRuby::QueryError)
      end

      it 'can include SQL that caused the error' do
        error = described_class.new('Syntax error', sql: 'SELEC * FROM table')
        expect(error.sql).to eq('SELEC * FROM table')
      end
    end

    describe ClickhouseRuby::StatementInvalid do
      it 'inherits from QueryError' do
        expect(described_class.superclass).to eq(ClickhouseRuby::QueryError)
      end
    end

    describe ClickhouseRuby::QueryTimeout do
      it 'inherits from QueryError' do
        expect(described_class.superclass).to eq(ClickhouseRuby::QueryError)
      end
    end

    describe ClickhouseRuby::UnknownTable do
      it 'inherits from QueryError' do
        expect(described_class.superclass).to eq(ClickhouseRuby::QueryError)
      end
    end

    describe ClickhouseRuby::UnknownColumn do
      it 'inherits from QueryError' do
        expect(described_class.superclass).to eq(ClickhouseRuby::QueryError)
      end
    end

    describe ClickhouseRuby::UnknownDatabase do
      it 'inherits from QueryError' do
        expect(described_class.superclass).to eq(ClickhouseRuby::QueryError)
      end
    end
  end

  describe ClickhouseRuby::TypeCastError do
    it 'inherits from ClickhouseRuby::Error' do
      expect(described_class.superclass).to eq(ClickhouseRuby::Error)
    end

    it 'accepts from_type' do
      error = described_class.new('Cast failed', from_type: 'String')
      expect(error.from_type).to eq('String')
    end

    it 'accepts to_type' do
      error = described_class.new('Cast failed', to_type: 'Int32')
      expect(error.to_type).to eq('Int32')
    end

    it 'accepts value' do
      error = described_class.new('Cast failed', value: 'invalid')
      expect(error.value).to eq('invalid')
    end

    it 'accepts all parameters' do
      error = described_class.new(
        'Cannot cast String to Int32',
        from_type: 'String',
        to_type: 'Int32',
        value: 'hello'
      )

      expect(error.from_type).to eq('String')
      expect(error.to_type).to eq('Int32')
      expect(error.value).to eq('hello')
    end
  end

  describe ClickhouseRuby::ConfigurationError do
    it 'inherits from ClickhouseRuby::Error' do
      expect(described_class.superclass).to eq(ClickhouseRuby::Error)
    end
  end

  describe 'Pool errors' do
    describe ClickhouseRuby::PoolError do
      it 'inherits from ClickhouseRuby::Error' do
        expect(described_class.superclass).to eq(ClickhouseRuby::Error)
      end
    end

    describe ClickhouseRuby::PoolExhausted do
      it 'inherits from PoolError' do
        expect(described_class.superclass).to eq(ClickhouseRuby::PoolError)
      end
    end

    describe ClickhouseRuby::PoolTimeout do
      it 'inherits from PoolError' do
        expect(described_class.superclass).to eq(ClickhouseRuby::PoolError)
      end
    end
  end

  describe 'Error code mapping' do
    describe 'ClickhouseRuby::ERROR_CODE_MAPPING' do
      it 'maps code 60 to UnknownTable' do
        expect(ClickhouseRuby::ERROR_CODE_MAPPING[60]).to eq(ClickhouseRuby::UnknownTable)
      end

      it 'maps code 16 to UnknownColumn' do
        expect(ClickhouseRuby::ERROR_CODE_MAPPING[16]).to eq(ClickhouseRuby::UnknownColumn)
      end

      it 'maps code 81 to UnknownDatabase' do
        expect(ClickhouseRuby::ERROR_CODE_MAPPING[81]).to eq(ClickhouseRuby::UnknownDatabase)
      end

      it 'maps code 62 to SyntaxError' do
        expect(ClickhouseRuby::ERROR_CODE_MAPPING[62]).to eq(ClickhouseRuby::SyntaxError)
      end

      it 'maps code 159 to QueryTimeout' do
        expect(ClickhouseRuby::ERROR_CODE_MAPPING[159]).to eq(ClickhouseRuby::QueryTimeout)
      end

      it 'is frozen' do
        expect(ClickhouseRuby::ERROR_CODE_MAPPING).to be_frozen
      end
    end

    describe 'ClickhouseRuby.error_class_for_code' do
      it 'returns mapped error class for known codes' do
        expect(ClickhouseRuby.error_class_for_code(60)).to eq(ClickhouseRuby::UnknownTable)
        expect(ClickhouseRuby.error_class_for_code(62)).to eq(ClickhouseRuby::SyntaxError)
      end

      it 'returns QueryError for unknown codes' do
        expect(ClickhouseRuby.error_class_for_code(999)).to eq(ClickhouseRuby::QueryError)
        expect(ClickhouseRuby.error_class_for_code(1)).to eq(ClickhouseRuby::QueryError)
      end
    end
  end

  describe 'Error hierarchy for rescue' do
    # Verify that errors can be caught at appropriate levels
    it 'allows catching all errors with ClickhouseRuby::Error' do
      errors = [
        ClickhouseRuby::ConnectionError.new,
        ClickhouseRuby::ConnectionNotEstablished.new,
        ClickhouseRuby::QueryError.new,
        ClickhouseRuby::SyntaxError.new,
        ClickhouseRuby::TypeCastError.new,
        ClickhouseRuby::ConfigurationError.new,
        ClickhouseRuby::PoolError.new
      ]

      errors.each do |error|
        expect { raise error }.to raise_error(ClickhouseRuby::Error)
      end
    end

    it 'allows catching connection errors specifically' do
      expect { raise ClickhouseRuby::ConnectionNotEstablished }.to raise_error(ClickhouseRuby::ConnectionError)
      expect { raise ClickhouseRuby::ConnectionTimeout }.to raise_error(ClickhouseRuby::ConnectionError)
      expect { raise ClickhouseRuby::SSLError }.to raise_error(ClickhouseRuby::ConnectionError)
    end

    it 'allows catching query errors specifically' do
      expect { raise ClickhouseRuby::SyntaxError }.to raise_error(ClickhouseRuby::QueryError)
      expect { raise ClickhouseRuby::UnknownTable }.to raise_error(ClickhouseRuby::QueryError)
      expect { raise ClickhouseRuby::QueryTimeout }.to raise_error(ClickhouseRuby::QueryError)
    end

    it 'allows catching pool errors specifically' do
      expect { raise ClickhouseRuby::PoolExhausted }.to raise_error(ClickhouseRuby::PoolError)
      expect { raise ClickhouseRuby::PoolTimeout }.to raise_error(ClickhouseRuby::PoolError)
    end
  end
end
