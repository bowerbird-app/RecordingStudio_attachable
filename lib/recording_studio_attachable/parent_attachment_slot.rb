# frozen_string_literal: true

module RecordingStudioAttachable
  module ParentAttachmentSlot
    module_function

    def frame_dom_id(recording)
      "parent-attachment-#{recording.id}"
    end

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

    def locals(recording:, return_to:)
      configuration_locals(recording).merge(
        recording: recording,
        attachment_recording: attachment_recording_for(recording),
        return_to: return_to,
        redirect_params: redirect_params(return_to:)
      ).merge(copy_locals(recording))
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

    def copy_locals(recording)
      {
        replace_button_text: replace_button_text(recording),
        add_button_text: add_button_text(recording),
        empty_state_title: empty_state_title(recording),
        empty_state_description: empty_state_description(recording)
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

    def replace_button_text(recording)
      copy_for(recording, image: "Replace photo", file: "Replace file", default: "Replace")
    end

    def add_button_text(recording)
      copy_for(recording, image: "Add photo", file: "Add file", default: "Add file")
    end

    def empty_state_title(recording)
      copy_for(recording, image: "No photo yet", file: "No file yet", default: "No file yet")
    end

    def empty_state_description(recording)
      copy_for(recording, image: "Choose a photo to show here.", file: "Choose a file to attach here.",
                          default: "Choose a file to attach here.")
    end

    def copy_for(recording, image:, file:, default:)
      kinds = Array(configured_option(recording, :enabled_attachment_kinds)).map(&:to_sym)
      return image if kinds == [:image]
      return file if kinds == [:file]

      default
    end
  end
end
