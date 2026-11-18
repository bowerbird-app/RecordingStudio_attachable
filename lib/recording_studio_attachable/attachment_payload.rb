# frozen_string_literal: true

module RecordingStudioAttachable
  module AttachmentPayload
    module_function

    def build(recording, actor:, url_mode: nil, rails_url: nil)
      attachment = recording.recordable
      {
        id: recording.id,
        kind: attachment.attachment_kind,
        name: attachment.name,
        urls: {
          file: file_url(recording, attachment, actor: actor, url_mode: url_mode, rails_url: rails_url)
        }
      }
    end

    def file_url(recording, attachment, actor:, url_mode:, rails_url:)
      return unless Authorization.allowed?(action: :view, actor: actor, recording: recording)

      attachment.original_url(mode: url_mode, rails_url: rails_path(recording, rails_url))
    end

    def rails_path(recording, rails_url)
      return rails_url if rails_url.present?

      Engine.routes.url_helpers.attachment_file_path(recording)
    end
  end
end
