# frozen_string_literal: true

require "test_helper"
require "base64"
require "stringio"

class AttachmentPreviewTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TEST_IMAGE = Base64.strict_decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFElEQVR4nGP8z8DAwMDAxMDAwMDAAAANHQEDasKb6QAAAABJRU5ErkJggg=="
  ).freeze

  def test_authorized_preview_route_processes_a_real_image
    sign_in User.create!(email: "preview-test@example.com", password: "password123")

    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(TEST_IMAGE),
      filename: "avatar.png",
      content_type: "image/png"
    )
    file = Struct.new(:blob) do
      def variable?
        true
      end
    end.new(blob)
    attachment = Struct.new(:file, :original_filename, :content_type) do
      def preview_target_named(name)
        file.blob.variant(RecordingStudioAttachable.configuration.image_variant(name))
      end
    end.new(file, "avatar.png", "image/png")
    recording = Struct.new(:id, :recordable_type, :recordable).new(
      "attachment-preview",
      "RecordingStudioAttachable::Attachment",
      attachment
    )

    with_singleton_method(RecordingStudio::Recording, :find, ->(*) { recording }) do
      with_singleton_method(RecordingStudioAttachable::Authorization, :owner_recording_for, ->(*) { recording }) do
        with_singleton_method(RecordingStudioAttachable::Authorization, :owner_type_for, ->(*) {}) do
          with_singleton_method(RecordingStudioAttachable::Authorization, :authorize!, ->(*) { true }) do
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

  private

  def with_singleton_method(object, method_name, replacement)
    original = object.method(method_name)
    object.define_singleton_method(method_name, replacement)
    yield
  ensure
    object.define_singleton_method(method_name, original)
  end
end
