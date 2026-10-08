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
    assert_includes html, "aspect-square"
    assert_includes html, 'class="h-full w-full object-cover"'
    refute_includes html, "max-h-72"
    assert_equal 2, html.scan("bg-[var(--card-background-color)]").size
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
    assert_includes html, 'data-fp-style="danger"'
    assert_includes html, 'data-fp-style="default"'
    refute_includes html, 'data-fp-style="primary"'
    assert_operator html.index('name="attachment_collection[rows][][credit]"'), :<, html.index(">Trash<")
    assert_includes html, 'type="submit"'
    assert_includes html, 'type="button"'
    assert_includes html, "redirect_mode=return_to"
    assert_includes html, "return_to=%2Fattachment_editor"
    save_at = html.index("flat-pack--unsaved-changes")
    assert_operator html.index('value="delete"'), :<, save_at
    assert_operator html.index("</form>"), :<, save_at
    refute_includes html[save_at...html.index("</form>", save_at)], "<form"
    refute_includes html, "recording-studio-attachable--collection-order"
    refute_includes html, "recording-studio-attachable--collection-display"
    refute_includes html, "slideMedia"
    refute_includes html, "flat-pack--carousel"
    refute_includes html, ">Order<"
    refute_includes html, ">Slides<"
    refute_includes html, "Previous slide"
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

  def test_natural_preview_keeps_proportions_and_still_opens_the_original_file
    @row_preview = :natural
    html = render_editor(
      [child("image-1", name: "Pier", caption: "Light")],
      fields: [:caption],
      sortable: false,
      return_to: "/attachment_editor"
    )

    assert_includes html, 'src="/attachments/image-1/preview/med"'
    refute_includes html, "square_med"
    refute_includes html, "aspect-square"
    assert_includes html, "max-h-72"
    assert_includes html, "object-contain"
    assert_includes html, 'src="/attachments/image-1/file"'
    assert_includes html, 'role="dialog"'
  end

  def test_save_button_stays_default_until_a_field_changes
    html = render_editor(
      [child("image-1", name: "Pier", caption: "Light"), child("image-2", name: "Dock", caption: "Dawn")],
      fields: [:caption],
      sortable: false,
      return_to: "/attachment_editor"
    )

    save_form = html[/<form\b[^>]*flat-pack--unsaved-changes[^>]*>/]
    assert_match(/id="attachment-collection-parent-1"(?!-)/, save_form)
    save_at = html.index("flat-pack--unsaved-changes")
    inner = html[save_at...html.index("</form>", save_at)]
    save_button = inner.scan(/<button\b[^>]*>/).find { |tag| tag.include?('unsaved-changes-target="submit"') }

    assert_includes save_button, 'data-fp-style="default"'
    assert_includes save_button, 'form="attachment-collection-parent-1"'
    assert_match(/<div class="inline-flex">\s*<button[^>]*unsaved-changes-target="submit"/, inner)
    assert_includes inner, ">Save<"
    assert_includes html, 'hidden="hidden"'
    assert_includes html, 'id="attachment-collection-parent-1-trash-image-1"'
    assert_includes html, 'form="attachment-collection-parent-1-trash-image-1"'
    assert_includes html, 'id="attachment-collection-parent-1-trash-image-2"'
    refute_includes inner, "<form"
    refute_includes inner, 'data-fp-style="primary"'
  end

  def test_empty_editor_has_no_save_button
    @displays = %i[list carousel]
    html = render_editor([], fields: [:caption], sortable: false, return_to: "/attachment_editor")

    assert_includes html, "No images yet."
    refute_includes html, ">Save<"
    refute_includes html, ">Slides<"
  end

  def test_both_displays_keep_one_set_of_fields_and_open_on_the_list
    left = child("image-1", name: "Pier", caption: "Light")
    right = child("image-2", name: "Dock", caption: "Dawn")
    @displays = %i[list carousel]
    @default_display = :list
    html = render_editor(
      [left, right],
      fields: [:caption],
      sortable: false,
      return_to: "/attachment_editor"
    )

    assert_equal 1, html.scan('value="image-1"').size
    assert_equal 1, html.scan('value="image-2"').size
    assert_includes html, 'data-controller="recording-studio-attachable--collection-display"'
    assert_includes html, 'data-display="list"'
    assert_includes html, 'href="#list"'
    assert_includes html, 'href="#carousel"'
    assert_includes html, ">List<"
    assert_includes html, ">Slides<"
    assert_includes html, 'data-turbo="false"'
    assert_includes html, "collection-display#select"
    assert_includes html, 'aria-current="page"'
    assert_includes html, 'data-controller="flat-pack--carousel"'
    assert_equal 2, html.scan('data-flat-pack--carousel-target="slide"').size
    assert_equal 2, html.scan('collection-display-target="card"').size
    assert_equal 2, html.scan("bg-[var(--card-background-color)]").size
    assert_includes html, "group-data-[display=carousel]:sm:flex-col"
    assert_includes html, 'data-recording-studio-attachable--collection-display-target="carousel" hidden'
    assert_includes html, 'aria-label="Previous slide"'
    assert_includes html, 'aria-label="Next slide"'
    assert_equal 2, html.scan('data-recording-studio-attachable--collection-display-target="row"').size
    refute_match(/target="row"[^>]*hidden/, html)
    assert_equal 1, html.scan('src="/attachments/image-1/preview/square_med"').size
    assert_includes html, 'src="/attachments/image-1/file"'
    media_tag = html[/<div[^>]*target="slideMedia"[^>]*>/]
    assert_match(/(?<![\w-])hidden(?:=|\s|>)/, media_tag)
    assert_operator html.index('target="previewHome"'), :<, html.index("/preview/square_med")
  end

  def test_slides_open_on_the_first_image_with_the_other_rows_still_in_the_form
    @displays = [:carousel]
    @default_display = :carousel
    html = render_editor(
      [child("image-1", name: "Pier", caption: "Light"), child("image-2", name: "Dock", caption: "Dawn")],
      fields: [:caption],
      sortable: false,
      return_to: "/attachment_editor"
    )

    rows = html.scan(/<li[^>]*>/)
    assert_equal 2, rows.size
    assert(rows.all? { |row| row.include?("hidden") })
    assert_equal 2, html.scan('data-flat-pack--carousel-target="slide"').size
    assert_equal 2, html.scan('collection-display-target="card"').size
    assert_includes html, 'data-display="carousel"'
    assert_includes html, 'data-controller="flat-pack--carousel"'
    assert_includes html, "--carousel-viewport-background-color: transparent;"
    assert_operator html.index("flat-pack--carousel"), :<, html.index('value="image-1"')
    assert_equal 2, html.scan("bg-[var(--card-background-color)]").size
    assert_includes html, "aspect-square w-full overflow-hidden rounded-lg"
    assert_includes html, "aspect-ratio: 1/1"
    assert_includes html, 'data-flat-pack--carousel-side-preview-value="false"'
    assert_includes html, 'data-flat-pack--carousel-items-per-view-mobile-value="1"'
    assert_includes html, 'data-flat-pack--carousel-items-per-view-tablet-value="1"'
    assert_includes html, 'data-flat-pack--carousel-items-per-view-desktop-value="1"'
    assert_includes html, 'aria-label="Previous slide"'
    assert_includes html, 'data-lightbox-src="/attachments/image-1/file"'
    refute_includes html, 'target="carousel" hidden'
    refute_includes html, ">List<"
    refute_includes html, 'href="#list"'
    assert_equal 2, html.scan('name="attachment_collection[rows][][caption]"').size
    assert_includes html, "group-data-[display=carousel]:min-h-[26rem]"
    assert_includes html, "group-data-[display=carousel]:rounded-none"
    assert_includes html, "group-data-[display=carousel]:w-full"
    assert_includes html, "group-data-[display=carousel]:sm:items-stretch"
    media_tag = html[/<div[^>]*target="slideMedia"[^>]*>/]
    refute_match(/(?<![\w-])hidden(?:=|\s|>)/, media_tag)
    assert_operator html.index('target="slideMedia"'), :<, html.index("/preview/square_med")
    assert_operator html.index("/preview/square_med"), :<, html.index('target="previewHome"')
    assert_includes html, 'target="previewHome" hidden'
    assert_equal 1, html.scan('data-modal-id="attachment-image-image-1"').size
  end

  def test_one_slide_hides_the_pager
    @displays = [:carousel]
    html = render_editor(
      [child("image-1", name: "Pier", caption: "Light")],
      fields: [:caption],
      sortable: false,
      return_to: "/attachment_editor"
    )

    assert_includes html, 'data-display="carousel"'
    assert_includes html, 'data-controller="flat-pack--carousel"'
    refute_includes html, "Previous slide"
    refute_includes html, "Next slide"
    refute_includes html, "Go to slide"
  end

  def test_items_per_view_sets_how_many_cards_the_carousel_shows
    @displays = [:carousel]
    @items_per_view = { mobile: 1, tablet: 2, desktop: 3 }
    html = render_editor(
      [child("image-1", name: "Pier", caption: "Light"), child("image-2", name: "Dock", caption: "Dawn")],
      fields: [:caption],
      sortable: false,
      return_to: "/attachment_editor"
    )

    assert_includes html, 'data-flat-pack--carousel-items-per-view-mobile-value="1"'
    assert_includes html, 'data-flat-pack--carousel-items-per-view-tablet-value="2"'
    assert_includes html, 'data-flat-pack--carousel-items-per-view-desktop-value="3"'
  end

  def test_side_preview_peeks_the_next_slide
    @displays = [:carousel]
    @side_preview = true
    html = render_editor(
      [child("image-1", name: "Pier", caption: "Light"), child("image-2", name: "Dock", caption: "Dawn")],
      fields: [:caption],
      sortable: false,
      return_to: "/attachment_editor"
    )

    assert_includes html, 'data-flat-pack--carousel-side-preview-value="true"'
    assert_equal 2, html.scan('name="attachment_collection[rows][][caption]"').size
  end

  def test_natural_slides_use_a_wider_frame
    @displays = [:carousel]
    @row_preview = :natural
    html = render_editor(
      [child("image-1", name: "Pier", caption: "Light")],
      fields: [:caption],
      sortable: false,
      return_to: "/attachment_editor"
    )

    assert_includes html, "aspect-ratio: 4/3"
    refute_includes html, "aspect-ratio: 1/1"
  end

  def test_sortable_slides_keep_order_inputs_and_hide_the_reorder_controls
    image = child("image-1", name: "Pier", caption: "Light")
    parent = orderable_parent([image])
    @displays = %i[list carousel]
    @default_display = :carousel
    html = render_editor(
      [image],
      parent: parent,
      fields: [:caption],
      sortable: true,
      return_to: "/attachment_editor"
    )

    assert_includes html, 'name="attachment_collection[rows][][order]"'
    assert_includes html, 'value="1"'
    assert_includes html, 'data-recording-studio-attachable--collection-display-target="listOnly" hidden'
    assert_includes html, ">Drag<"
    assert_includes html, ">Order<"
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
        preview: @row_preview || :square,
        displays: @displays || [:list],
        default_display: @default_display,
        side_preview: @side_preview || false,
        items_per_view: @items_per_view || 1,
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
      lib/flat_pack/button/style_registry.rb
      app/components/flat_pack/base_component.rb
      app/components/flat_pack/shared/icon_component.rb
      app/components/flat_pack/button/pill_style.rb
      app/components/flat_pack/button/component.rb
      app/components/flat_pack/shared/pad_text_sizes.rb
      app/components/flat_pack/button/pill/component.rb
      app/components/flat_pack/form_field/control_styles.rb
      app/components/flat_pack/form_field/component.rb
      app/components/flat_pack/text_input/component.rb
      app/components/flat_pack/tooltip/component.rb
      app/components/flat_pack/modal/component.rb
      app/components/flat_pack/carousel/component.rb
      app/components/flat_pack/card/media/component.rb
      app/components/flat_pack/card/header/component.rb
      app/components/flat_pack/card/body/component.rb
      app/components/flat_pack/card/footer/component.rb
      app/components/flat_pack/card/component.rb
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
