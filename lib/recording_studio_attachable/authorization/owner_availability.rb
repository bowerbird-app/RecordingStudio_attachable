# frozen_string_literal: true

module RecordingStudioAttachable
  module Authorization
    module OwnerAvailability
      module_function

      def allowed?(action:, actor:, recording:)
        owner = Authorization.owner_recording_for(recording)
        recordable_class = owner_recordable_class(owner)
        return true unless recordable_class.is_a?(Module)
        return hook_result(owner, action, actor) if public_hook?(recordable_class)
        return false if hidden_hook?(recordable_class)

        true
      end

      def hook_result(owner, action, actor)
        result = owner.recordable.attachable_available_for?(actor: actor, action: action, recording: owner)
        result.equal?(true)
      rescue StandardError => e
        log_error(e)
        false
      end

      def public_hook?(recordable_class)
        recordable_class.public_method_defined?(:attachable_available_for?)
      end

      def hidden_hook?(recordable_class)
        recordable_class.private_method_defined?(:attachable_available_for?) ||
          recordable_class.protected_method_defined?(:attachable_available_for?)
      end

      def owner_recordable_class(owner)
        return unless owner.respond_to?(:recordable_type)

        name = owner.recordable_type.to_s
        return if name.blank?

        name.safe_constantize
      end

      def log_error(error)
        line = "RecordingStudioAttachable owner availability check failed (#{error.class})"
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.warn(line)
        else
          warn(line)
        end
      end
      private_class_method :hook_result, :public_hook?, :hidden_hook?, :owner_recordable_class, :log_error
    end
  end
end
