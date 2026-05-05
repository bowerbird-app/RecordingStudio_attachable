# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/attachment_uploads_controller"

module RecordingStudioAttachable
  class AttachmentUploadsControllerTest < ActionController::TestCase
    def test_attachment_payloads_permits_nested_json_attachment_fields
      @controller = AttachmentUploadsController.new
      @controller.send(
        :params=,
        ActionController::Parameters.new(
          attachments: [
            {
              signed_blob_id: "blob-1",
              name: "bike rack plans",
              description: ""
            }
          ],
          attachment_upload: {
            attachments: [
              {
                signed_blob_id: "blob-1",
                name: "bike rack plans",
                description: "",
                ignored: "value"
              }
            ]
          }
        )
      )

      assert_equal(
        [{ signed_blob_id: "blob-1", name: "bike rack plans", description: "" }],
        @controller.send(:attachment_payloads)
      )
    end
  end
end
