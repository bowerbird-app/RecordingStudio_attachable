# frozen_string_literal: true

require "test_helper"
require "action_view"
require "action_controller"
require "flat_pack"
require_relative "../app/helpers/recording_studio_attachable/attachment_file_buttons_helper"
require_relative "../app/helpers/recording_studio_attachable/attachment_collections_helper"
require_relative "../app/helpers/recording_studio_attachable/application_helper"
require_relative "../app/queries/recording_studio_attachable/queries/for_recording"

class AttachmentCollectionsHelperTest < Minitest::Test
  Parent = Struct.new(:id)
  Snapshot = Struct.new(:name, :description, :caption, :credit, :alt_text, :original_filename, keyword_init: true)
  Child = Struct.new(:id, :created_at, :recordable, keyword_init: true)

  def test_editor_renders_one_square_med_preview_per_row_and_only_the_requested_fields
    left = child("image-1", name: "Pier", caption: "Light", credit: "Ada")
    right = child("image-2", name: "Dock", caption: "Dawn", credit: "Bea")
    html = render_editor([left, right], fields: %i[caption credit], sortable: false, return_to: "/attachment_editor")

    assert_equal 2, html.scan('src="/attachments/image-1/preview/square_med"').size +
                    html.scan('src="/attachments/image-2/preview/square_med"').size
    assert_includes html, 'src="/attachments/image-1/preview/square_med"'
    assert_includes html, 'src="/attachments/image-2/preview/square_med"'
    assert_includes html, 'alt="Pier"'
    assert_includes html, 'data-modal-id="attachment-image-image-1"'
    assert_includes html, 'src="/attachments/image-1/file"'
    assert_includes html, 'role="dialog"'
    refute_includes html, ">Open<"
    refute_includes html, 'href="/attachments/image-1/file"'
    assert_includes html, ">Caption<"
    assert_includes html, ">Credit<"
    assert_includes html, 'name="attachment_collection[rows][][caption]"'
    assert_includes html, 'form="attachment-collection-parent-1"'
    refute_includes html, "Alt text"
    refute_includes html, "Change"
    refute_includes html, "signed_blob"
    assert_includes html, ">Save<"
    assert_includes html, 'value="delete"'
    assert_includes html, ">Trash<"
    assert_includes html, 'data-flat-pack--icon-name-value="trash"'
    assert_includes html, "button-danger-background-color"
    assert_operator html.index('name="attachment_collection[rows][][credit]"'), :<, html.index('value="delete"')
    assert_includes html, 'type="submit"'
    assert_includes html, 'type="button"'
    assert_includes html, "redirect_mode=return_to"
    assert_includes html, "return_to=%2Fattachment_editor"
    assert_operator html.index("</form>"), :<, html.index('value="delete"')
    refute_includes html, "recording-studio-attachable--collection-order"
    refute_includes html, ">Order<"
  end

  def test_sortable_editor_posts_order_numbers_and_omits_them_when_sorting_is_off
    image = child("image-1", name: "Pier", caption: "Light")
    parent = orderable_parent([image])
    html = render_editor([image], parent: parent, fields: [:caption], sortable: true, return_to: "/attachment_editor")

    assert_includes html, 'data-controller="recording-studio-attachable--collection-order"'
    assert_includes html, ">Order<"
    assert_includes html, 'name="attachment_collection[rows][][order]"'
    assert_includes html, 'value="1"'
  end

  def test_empty_editor_has_no_save_button
    html = render_editor([], fields: [:caption], sortable: false, return_to: "/attachment_editor")

    assert_includes html, "No images yet."
    refute_includes html, ">Save<"
  end

  private

  def render_editor(recordings, fields:, sortable:, return_to:, parent: Parent.new("parent-1"))
    query = Object.new
    query.define_singleton_method(:unpaged) { recordings }
    RecordingStudioAttachable::Queries::ForRecording.stub(:new, ->(**) { query }) do
      editor_view.attachment_collection_editor(
        parent,
        association: :images,
        fields: fields,
        sortable: sortable,
        url: "/save",
        return_to: return_to
      )
    end
  end

  def editor_view
    return @editor_view if defined?(@editor_view)

    load_flat_pack_components!
    paths = [RecordingStudioAttachable::Engine.root.join("app/views")]
    controller = ActionController::Base.new
    controller.request = ActionDispatch::TestRequest.create
    controller.response = ActionDispatch::TestResponse.new
    view = ActionView::Base.with_empty_template_cache.with_view_paths(paths, {}, controller)
    view.extend(RecordingStudioAttachable::ApplicationHelper)
    view.define_singleton_method(:authorized_attachment_preview_path) do |recording, variant|
      "/attachments/#{recording.id}/preview/#{variant}"
    end
    view.define_singleton_method(:authorized_attachment_file_path) do |recording|
      "/attachments/#{recording.id}/file"
    end
    view.define_singleton_method(:attachable_destroy_attachment_path) do |recording, **options|
      query = options.map { |key, value| "#{key}=#{CGI.escape(value.to_s)}" }.join("&")
      "/attachments/#{recording.id}?#{query}"
    end
    @editor_view = view
  end

  def load_flat_pack_components!
    root = Gem.loaded_specs.fetch("flat_pack").full_gem_path
    %w[
      app/components/flat_pack/base_component.rb
      app/components/flat_pack/shared/icon_component.rb
      app/components/flat_pack/button/component.rb
      app/components/flat_pack/text_input/component.rb
      app/components/flat_pack/tooltip/component.rb
      app/components/flat_pack/modal/component.rb
    ].each { |path| require File.join(root, path) }
  end

  def orderable_parent(children)
    parent = Parent.new("parent-1")
    parent.define_singleton_method(:recording_studio_orderable_children) { children }
    parent.define_singleton_method(:recording_studio_orderable_reorder!) { |**| nil }
    parent
  end

  def child(id, name:, caption: nil, credit: nil)
    Child.new(
      id: id,
      created_at: Time.utc(2026, 1, 1),
      recordable: Snapshot.new(
        name: name,
        description: nil,
        caption: caption,
        credit: credit,
        alt_text: "Hidden alt",
        original_filename: "#{id}.png"
      )
    )
  end
end
