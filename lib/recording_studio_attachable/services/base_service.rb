# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class BaseService
      HANDLED_EXCEPTIONS = [
        ArgumentError,
        ActiveRecord::ActiveRecordError,
        ActiveSupport::MessageVerifier::InvalidSignature,
        RecordingStudioAttachable::Error
      ].freeze

      class Result
        attr_reader :value, :error, :errors

        def initialize(success:, value: nil, error: nil, errors: [])
          @success = success
          @value = value
          @error = error
          @errors = errors
        end

        def success?
          @success
        end

        def failure?
          !@success
        end

        def on_success
          yield(value) if success? && block_given?
          self
        end

        def on_failure
          yield(error, errors) if failure? && block_given?
          self
        end
      end

      class << self
        def call(*, **, &)
          new(*, **).call(&)
        end
      end

      def call
        result = perform
        yield(result) if block_given?
        result
      rescue *HANDLED_EXCEPTIONS => e
        failure(e)
      end

      private

      def perform
        raise NotImplementedError, "#{self.class}#perform must be implemented"
      end

      def success(value = nil)
        Result.new(success: true, value: value)
      end

      def failure(error, errors: [])
        message = error.is_a?(Exception) ? error.message : error
        Result.new(success: false, error: message, errors: errors)
      end
    end
  end
end
