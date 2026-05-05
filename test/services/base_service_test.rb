# frozen_string_literal: true

require "test_helper"

module RecordingStudioAttachable
  module Services
    class BaseServiceTest < Minitest::Test
      class TestService < BaseService
        def initialize(should_succeed:, value: nil, error: nil)
          @should_succeed = should_succeed
          @value = value
          @error = error
        end

        private

        def perform
          @should_succeed ? success(@value) : failure(@error)
        end
      end

      class HandledExceptionService < BaseService
        private

        def perform
          raise ArgumentError, "bad input"
        end
      end

      class UnexpectedExceptionService < BaseService
        private

        def perform
          raise NoMethodError, "boom"
        end
      end

      def test_call_returns_success_result
        result = TestService.call(should_succeed: true, value: "ok")

        assert result.success?
        assert_equal "ok", result.value
      end

      def test_call_returns_failure_result
        result = TestService.call(should_succeed: false, error: "bad")

        assert result.failure?
        assert_equal "bad", result.error
      end

      def test_call_wraps_expected_domain_errors
        result = HandledExceptionService.call

        assert result.failure?
        assert_equal "bad input", result.error
      end

      def test_call_re_raises_unexpected_errors
        assert_raises(NoMethodError) { UnexpectedExceptionService.call }
      end

      def test_result_on_success_yields_value_and_returns_self
        result = BaseService::Result.new(success: true, value: "ok")
        yielded_value = nil

        returned = result.on_success do |value|
          yielded_value = value
        end

        assert_same result, returned
        assert_equal "ok", yielded_value
      end

      def test_result_on_failure_yields_error_and_errors_and_returns_self
        result = BaseService::Result.new(success: false, error: "bad", errors: [:details])
        yielded = nil

        returned = result.on_failure do |error, errors|
          yielded = [error, errors]
        end

        assert_same result, returned
        assert_equal ["bad", [:details]], yielded
      end

      def test_call_yields_result_to_block
        yielded_result = nil

        result = TestService.call(should_succeed: true, value: "ok") do |service_result|
          yielded_result = service_result
        end

        assert_same result, yielded_result
      end

      def test_failure_uses_exception_message
        result = TestService.call(
          should_succeed: false,
          error: ArgumentError.new("invalid")
        )

        assert result.failure?
        assert_equal "invalid", result.error
      end

      def test_base_service_requires_subclasses_to_implement_perform
        abstract_service = Class.new(BaseService)

        assert_raises(NotImplementedError) { abstract_service.call }
      end
    end
  end
end
