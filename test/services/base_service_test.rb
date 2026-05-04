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
    end
  end
end
