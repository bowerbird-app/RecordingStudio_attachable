# frozen_string_literal: true

require "test_helper"
require "base64"
require "digest"

class ActiveStorageRoutesTest < ActionDispatch::IntegrationTest
  PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
  ).freeze

  test "an anonymous rails direct upload is not routed" do
    assert_not Rails.application.routes.named_routes.names.include?(:rails_direct_uploads)
    assert_not Rails.application.routes.named_routes.names.include?(:rails_service_blob_proxy)
    before = ActiveStorage::Blob.count

    post "/rails/active_storage/direct_uploads",
         params: {
           blob: {
             filename: "note.png",
             byte_size: PNG.bytesize,
             checksum: Digest::MD5.base64digest(PNG),
             content_type: "image/png"
           }
         },
         as: :json

    assert_response :not_found
    assert_equal before, ActiveStorage::Blob.count
  end

  test "a signed blob redirect and representation redirect still resolve" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(PNG),
      filename: "dot.png",
      content_type: "image/png"
    )

    get rails_blob_path(blob)

    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_equal PNG, response.body

    variant = blob.variant(resize_to_limit: [1, 1]).processed
    get rails_representation_path(variant)

    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_operator response.body.bytesize, :>, 0
  end

  test "disk show and update stay routed for the disk service" do
    names = Rails.application.routes.named_routes.names

    assert_includes names, :rails_service_blob
    assert_includes names, :rails_blob_representation
    assert_includes names, :rails_disk_service
    assert_includes names, :update_rails_disk_service
  end
end
