# frozen_string_literal: true

module RecordingStudioAttachable
  module AttachmentChrome
    KIND_FILE_BUTTON = "file_button"
    KIND_IMAGE_SLOT = "image_slot"
    KINDS = [KIND_FILE_BUTTON, KIND_IMAGE_SLOT].freeze

    DEFAULT_SHAPE = :circle
    DEFAULT_SIZE = :xl
    DEFAULT_ADD_LABEL = "Add"
    DEFAULT_CHANGE_LABEL = "Change"
    PARAM_KEY = :attachment_chrome

    module_function

    def frame_dom_id(recording, kind:)
      "attachment-chrome-#{kind}-#{recording.id}"
    end

    def redirect_params(return_to:)
      { redirect_mode: "return_to", return_to: return_to }.compact_blank
    end

    def return_to_from(redirect_params)
      return unless redirect_params[:redirect_mode] == "return_to"

      redirect_params[:return_to]
    end

    def from_params(params)
      raw = params[PARAM_KEY] || params[PARAM_KEY.to_s]
      raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
      raw = raw.to_h if raw.respond_to?(:to_h)
      return if raw.blank?

      kind = raw[:kind].presence || raw["kind"].presence
      return unless KINDS.include?(kind.to_s)

      identity_for(
        kind: kind,
        shape: raw[:shape].presence || raw["shape"].presence || DEFAULT_SHAPE,
        size: raw[:size].presence || raw["size"].presence || DEFAULT_SIZE,
        add_label: raw[:add_label].presence || raw["add_label"].presence || DEFAULT_ADD_LABEL,
        change_label: raw[:change_label].presence || raw["change_label"].presence || DEFAULT_CHANGE_LABEL
      )
    end

    def identity_for(kind:, shape: DEFAULT_SHAPE, size: DEFAULT_SIZE,
                     add_label: DEFAULT_ADD_LABEL, change_label: DEFAULT_CHANGE_LABEL)
      {
        kind: kind.to_s,
        shape: shape.to_sym,
        size: size.to_sym,
        add_label: add_label,
        change_label: change_label
      }
    end

    def locals(recording:, return_to:, identity:)
      configuration_locals(recording).merge(
        recording: recording,
        attachment_recording: attachment_recording_for(recording),
        return_to: return_to,
        redirect_params: redirect_params(return_to:),
        chrome_kind: identity.fetch(:kind),
        avatar_shape: identity.fetch(:shape),
        avatar_size: identity.fetch(:size),
        add_label: identity.fetch(:add_label),
        change_label: identity.fetch(:change_label),
        chrome_params: identity
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
