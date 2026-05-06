# frozen_string_literal: true

require "test_helper"

class DummyUploadProviderDemoTest < Minitest::Test
  def test_dummy_app_registers_demo_upload_provider
    initializer = File.read(File.expand_path("dummy/config/initializers/recording_studio_attachable.rb", __dir__))

    assert_includes initializer, "config.google_drive.enabled = true"
    assert_includes initializer, "DUMMY_GOOGLE_DRIVE_CLIENT_ID"
    assert_includes initializer, "DUMMY_GOOGLE_DRIVE_CLIENT_SECRET"
    assert_includes initializer, "DUMMY_GOOGLE_DRIVE_API_KEY"
    assert_includes initializer, "DUMMY_GOOGLE_DRIVE_APP_ID"
    assert_includes initializer, "/recording_studio_attachable/google_drive/oauth/callback"
    assert_includes initializer, "config.register_upload_provider("
    assert_includes initializer, ":demo_cloud"
    assert_includes initializer, 'label: "Demo cloud import"'
    assert_includes initializer, "route_helpers.demo_upload_provider_path(recording_id: recording.id)"
  end

  def test_dummy_app_exposes_demo_upload_provider_route_and_page
    routes = File.read(File.expand_path("dummy/config/routes.rb", __dir__))
    controller = File.read(File.expand_path("dummy/app/controllers/upload_providers_controller.rb", __dir__))
    view = File.read(File.expand_path("dummy/app/views/upload_providers/show.html.erb", __dir__))

    assert_includes routes, 'get "upload_providers/demo", to: "upload_providers#show", as: :demo_upload_provider'
    assert_includes routes, 'post "upload_providers/demo", to: "upload_providers#create"'
    assert_includes controller, "RecordingStudioAttachable::Services::ImportAttachment.call"
    assert_includes controller, 'filename: "demo-cloud-import.svg"'
    assert_includes controller, 'content_type: "image/svg+xml"'
    assert_includes controller, 'source: "demo_cloud"'
    assert_includes view, 'title: "Demo cloud import"'
    assert_includes view, 'subtitle: "Reference provider flow for recording ##{@recording.id}"'
    assert_includes view, "This dummy page uses the public provider import API"
    assert_includes view, 'text: "Import sample SVG"'
    assert_includes view, "recording_studio_attachable.recording_attachment_upload_path(@recording)"
    assert_includes view, 'text: "Back to upload page"'
    assert_match(/<div class="mx-auto flex w-full max-w-4xl flex-col gap-6">\s*<%= render FlatPack::Breadcrumb::Component.new\(/m, view)
  end
end
