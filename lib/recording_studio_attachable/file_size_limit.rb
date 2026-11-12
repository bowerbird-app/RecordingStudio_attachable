# frozen_string_literal: true

module RecordingStudioAttachable
  # Optional per-item plan cap. The plan can lower a parent type's code max.
  # It cannot raise that max. A nil ceiling leaves the code max in place.
  module FileSizeLimit
    Cap = Struct.new(:max_bytes, :plan_lowered)

    class << self
      def enabled?
        configured_name.present? && defined?(RecordingStudioStripe)
      end

      def cap_for(recording, code_max)
        code, plan, = read(recording, code_max)
        Cap.new([code, plan].compact.min, lowered?(code, plan))
      end

      def effective_max(recording, code_max)
        cap_for(recording, code_max).max_bytes
      end

      def lowers?(recording, code_max)
        cap_for(recording, code_max).plan_lowered
      end

      def enforce!(recording, bytes, code_max:)
        code, plan, handle = read(recording, code_max)
        size = integer_size(bytes)
        return unless blocks?(code, plan, size)

        handle.enforce_item!(size)
      end

      def plan_limit?(error)
        defined?(RecordingStudioStripe::PlanLimitReached) && error.is_a?(RecordingStudioStripe::PlanLimitReached)
      end

      private

      def read(recording, code_max)
        code = numeric_max(code_max)
        return [code, nil, nil] unless enabled?

        handle = handle_for(recording)
        [code, handle.ceiling, handle]
      end

      def lowered?(code, plan)
        !plan.nil? && (code.nil? || plan < code)
      end

      def blocks?(code, plan, size)
        return false if plan.nil? || (code && plan >= code)

        size > plan && size.positive?
      end

      def handle_for(recording)
        limit_name = configured_name
        per_item_definition!(limit_name)
        root_for(recording).billing.limit(limit_name)
      rescue FileSizeLimitUnknown
        raise
      rescue ArgumentError
        raise FileSizeLimitUnknown, unknown_message(limit_name)
      end

      def per_item_definition!(limit_name)
        limits = RecordingStudioStripe::Limits
        raise FileSizeLimitUnknown, unknown_message(limit_name) unless limits.known?(limit_name)

        definition = limits.fetch(limit_name)
        return definition if definition.per_item?

        raise FileSizeLimitUnknown, "File size limit #{limit_name} is not a per-item limit"
      end

      def configured_name
        RecordingStudioAttachable.configuration.file_size_limit
      end

      def unknown_message(limit_name)
        "Unknown file size limit #{limit_name}"
      end

      def root_for(recording)
        return recording unless recording.respond_to?(:root_recording)

        recording.root_recording || recording
      end

      def numeric_max(value)
        return if value.nil? || blank_string?(value)

        value.is_a?(Integer) ? value : Integer(value)
      end

      def blank_string?(value)
        value.is_a?(String) && value.strip.empty?
      end

      def integer_size(bytes)
        Integer(bytes)
      rescue ArgumentError, TypeError
        bytes.to_i
      end
    end
  end
end
