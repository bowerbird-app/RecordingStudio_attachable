# frozen_string_literal: true

require "test_helper"
require "base64"
require "stringio"

class AttachmentPreviewTest < ActionDispatch::IntegrationTest
  TEST_IMAGE = Base64.strict_decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFElEQVR4nGP8z8DAwMDAxMDAwMDAAAANHQEDasKb6QAAAABJRU5ErkJggg=="
  ).freeze

  def test_authorized_preview_route_processes_a_real_image
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(TEST_IMAGE),
      filename: "avatar.png",
      content_type: "image/png"
    )
    attachment = RecordingStudioAttachable::Attachment.create!(
      name: "Avatar",
      attachment_kind: "image",
      original_filename: "avatar.png",
      content_type: "image/png",
      byte_size: TEST_IMAGE.bytesize
    )
    attachment.file.attach(blob)
    recording = Struct.new(:id, :recordable_type, :recordable).new(
      "attachment-preview",
      "RecordingStudioAttachable::Attachment",
      attachment
    )

    RecordingStudio::Recording.stub(:find, recording) do
      RecordingStudioAttachable::Authorization.stub(:owner_recording_for, recording) do
        RecordingStudioAttachable::Authorization.stub(:owner_type_for, nil) do
          RecordingStudioAttachable::Authorization.stub(:authorize!, true) do
            get "/recording_studio_attachable/attachments/#{recording.id}/preview/square_small"
          end
        end
      end
    end

    assert_response :success
    assert_equal "image/png", response.media_type
    assert_operator response.body.bytesize, :>, 0
  ensure
    blob&.purge
  end
end
