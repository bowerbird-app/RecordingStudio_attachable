# frozen_string_literal: true

module RecordingStudioAttachable
  module AttachmentFileButton
    DEFAULT_ADD_LABEL = "Add"
    DEFAULT_CHANGE_LABEL = "Change"

    module_function

    def redirect_params(return_to:)
      {
        redirect_mode: "return_to",
        return_to: return_to
      }.compact_blank
    end

    def return_to_from(redirect_params)
      return unless redirect_params[:redirect_mode] == "return_to"

      redirect_params[:return_to]
    end

    def locals(recording:, return_to:, target: nil,
               add_label: DEFAULT_ADD_LABEL, change_label: DEFAULT_CHANGE_LABEL)
      configuration_locals(recording).merge(
        recording: recording,
        attachment_recording: attachment_recording_for(recording),
        return_to: return_to,
        redirect_params: redirect_params(return_to:),
        turbo_frame_target: target,
        add_label: add_label,
        change_label: change_label
      )
    end

    def configuration_locals(recording)
      {
        allowed_content_types: configured_option(recording, :allowed_content_types),
        max_file_size: configured_option(recording, :max_file_size),
        image_processing_enabled: configured_option(recording, :image_processing_enabled),
        image_processing_max_width: configured_option(recording, :image_processing_max_width),
        image_processing_max_height: configured_option(recording, :image_processing_max_height),
        image_processing_quality: configured_option(recording, :image_processing_quality)
      }
    end

    def accept_attribute(allowed_content_types)
      Array(allowed_content_types).join(",")
    end

    def attachment_recording_for(recording)
      return unless recording.respond_to?(:attachments)

      recording.attachments(scope: :direct, per_page: 1).first
    end

    def configured_option(recording, option_name)
      owner_type = recording.recordable_type
      capability_options =
        if defined?(RecordingStudio) && owner_type.present?
          RecordingStudio.capability_options(:attachable, for_type: owner_type) || {}
        else
          {}
        end

      capability_options.fetch(option_name) do
        RecordingStudioAttachable.configuration.public_send(option_name)
      end
    end
  end
end
