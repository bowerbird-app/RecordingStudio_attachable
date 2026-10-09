# frozen_string_literal: true

require "test_helper"
require_relative "../app/helpers/recording_studio_attachable/application_helper"

class LibraryViewsTest < Minitest::Test
  def test_attachment_show_edits_caption_credit_and_alt
    source = File.read(File.expand_path("../app/views/recording_studio_attachable/attachments/show.html.erb", __dir__))

    assert_includes source, 'name: "attachment[caption]"'
    assert_includes source, 'name: "attachment[credit]"'
    assert_includes source, 'name: "attachment[alt_text]"'
    assert_includes source, "placement_usages"
    assert_includes source, "used_in"
    assert_includes source, "trash_in_use"
  end

  def test_placements_index_reuses_the_library_picker
    source = File.read(File.expand_path("../app/views/recording_studio_attachable/placements/index.html.erb", __dir__))

    assert_includes source, "recording-studio-attachable--attachment-image-picker"
    assert_includes source, "recording_attachment_picker_path(@library)"
    assert_includes source, "recording_attachments_path(@library)"
    assert_includes source, "FlatPack::Select::Component"
    assert_includes source, "switchLibrary"
    assert_includes source, 'text: t("recording_studio_attachable.placements.add")'
    assert_includes source, 'text: t("recording_studio_attachable.placements.upload")'
    assert_includes source, "attachment_image_pickers/modal"
    refute_includes source, "recordable"
    refute_includes source, "Recordable"
  end

  def test_library_and_placement_models_declare_product_labels
    library = File.read(File.expand_path("../app/models/recording_studio_attachable/library.rb", __dir__))
    placement = File.read(File.expand_path("../app/models/recording_studio_attachable/placement.rb", __dir__))

    assert_includes library, 'label: "Image library"'
    refute_includes library, "allowed_parent_types:"
    assert_includes placement, 'label: "Image"'
    refute_includes placement, "allowed_parent_types:"
    refute_includes library, "Recordable"
    refute_includes placement, "Recordable"
  end

  def test_locales_avoid_backend_words
    source = File.read(File.expand_path("../config/locales/recording_studio_attachable.en.yml", __dir__))

    refute_includes source, "recordable"
    refute_includes source, "capability"
    refute_includes source, "Recordable"
  end

  def test_library_placement_controller_submits_the_picked_image
    source = File.read(
      File.expand_path("../app/javascript/controllers/recording_studio_attachable/library_placement_controller.js", __dir__)
    )

    assert_includes source, 'static targets = ["form", "attachmentId", "uploadLibraryId", "switcher"]'
    assert_includes source, "addFromLibrary(event)"
    assert_includes source, "this.formTarget.requestSubmit()"
    assert_includes source, "browseUpload(event)"
    assert_includes source, "switchLibrary(event)"
    assert_includes source, 'form?.querySelector("input[type=file]")'
  end

  def test_libraries_index_is_gone
    refute File.exist?(File.expand_path("../app/views/recording_studio_attachable/libraries/index.html.erb", __dir__))

    routes = File.read(File.expand_path("../config/routes.rb", __dir__))
    assert_includes routes, "resource :library, only: :show, controller: \"libraries\""
    assert_includes routes, 'get "libraries/:id", to: "libraries#show", as: :library'
    refute_includes routes, "resources :libraries"
    refute_includes routes, "libraries#update"
    refute_includes routes, "libraries#destroy"
    refute_includes routes, "libraries#index"
    refute_includes routes, "libraries#create"
  end

  def test_helper_mounts_a_library_or_parent_plus_key
    helper = Object.new
    helper.extend(RecordingStudioAttachable::ApplicationHelper)
    library = Struct.new(:id, :recordable_type).new("lib-1", "RecordingStudioAttachable::Library")
    parent = Struct.new(:id, :recordable_type).new("root-1", "Workspace")
    routes = Object.new
    routes.define_singleton_method(:library_path) { |item, **| "/libraries/#{item.id}" }
    routes.define_singleton_method(:recording_library_path) do |item, **options|
      "/recordings/#{item.id}/library?key=#{options[:key]}"
    end
    helper.define_singleton_method(:attachable_routes) { routes }

    assert_equal "/libraries/lib-1", helper.library_path_for(library)
    assert_equal "/recordings/root-1/library?key=campaign", helper.library_path_for(parent, key: :campaign)
  end

  def test_locales_keep_host_labels_and_drop_user_library_forms
    source = File.read(File.expand_path("../config/locales/recording_studio_attachable.en.yml", __dir__))

    assert_includes source, "keys:"
    assert_includes source, 'default: "Images"'
    refute_includes source, "Create library"
    refute_includes source, "Rename"
    refute_includes source, "Give the library a name"
  end

  def test_helper_reorders_placement_ids
    helper = Object.new
    helper.extend(RecordingStudioAttachable::ApplicationHelper)
    first = Struct.new(:placement_recording).new(Struct.new(:id).new("place-1"))
    second = Struct.new(:placement_recording).new(Struct.new(:id).new("place-2"))
    resolved = [first, second]

    assert_equal %w[place-2 place-1], helper.move_placement_ids(resolved, 0, 1)
    assert_equal %w[place-1 place-2], helper.move_placement_ids(resolved, 0, -1)
  end

  def test_helper_builds_picker_switcher_payload
    helper = Object.new
    helper.extend(RecordingStudioAttachable::ApplicationHelper)
    library = Struct.new(:id).new("lib-1")
    routes = Object.new
    routes.define_singleton_method(:recording_attachment_picker_path) { |item| "/picker/#{item.id}" }
    routes.define_singleton_method(:recording_attachments_path) { |item| "/upload/#{item.id}" }
    helper.define_singleton_method(:attachable_routes) { routes }

    assert_equal(
      { "lib-1" => { pickerUrl: "/picker/lib-1", uploadUrl: "/upload/lib-1" } },
      helper.library_picker_switcher_payload([library])
    )
  end
end
