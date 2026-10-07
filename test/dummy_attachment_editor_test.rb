# frozen_string_literal: true

require "test_helper"

class DummyAttachmentEditorTest < Minitest::Test
  def test_dummy_attachment_editor_edits_workspace_images_without_sorting
    controller = File.read(File.expand_path("dummy/app/controllers/attachment_editors_controller.rb", __dir__))
    view = File.read(File.expand_path("dummy/app/views/attachment_editors/show.html.erb", __dir__))
    routes = File.read(File.expand_path("dummy/config/routes.rb", __dir__))
    home = File.read(File.expand_path("dummy/app/views/home/index.html.erb", __dir__))
    home_controller = File.read(File.expand_path("dummy/app/controllers/home_controller.rb", __dir__))
    layout = File.read(File.expand_path("dummy/app/views/layouts/application.html.erb", __dir__))
    gemfile = File.read(File.expand_path("../Gemfile", __dir__))

    assert_includes routes, 'get "attachment_editor", to: "attachment_editors#show", as: :attachment_editor'
    refute_includes controller, "UsesDefaultLayout"
    assert_includes controller, "RecordingStudio.root_recording_for(Workspace.first!)"
    assert_includes controller, "@return_to = attachment_editor_path"
    assert_includes view, 'title: "Edit images"'
    assert_includes view, "attachment_collection_editor("
    assert_includes view, "association: :images"
    assert_includes view, "fields: [:caption, :credit, :alt_text]"
    assert_includes view, "sortable: false"
    assert_includes view, "displays: [:list, :carousel]"
    assert_includes view, "default_display: :list"
    assert_includes view, "side_preview: true"
    assert_includes view, "items_per_view: { mobile: 1, tablet: 1, desktop: 2 }"
    assert_includes view, "return_to: @return_to"
    assert_includes home, 'text: "Edit images"'
    assert_includes home_controller, "@attachment_editor_path = attachment_editor_path"
    assert_includes layout, '<html data-theme="rounded">'
    refute_includes gemfile, "recording_studio_orderable"
  end
end
