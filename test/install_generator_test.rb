# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_attachable/install/install_generator"

class InstallGeneratorTest < Minitest::Test
  def with_temp_app
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "app/assets/tailwind"))
      FileUtils.mkdir_p(File.join(dir, "app/javascript/controllers"))
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config/importmap.rb"), "pin_all_from 'app/javascript/controllers', under: 'controllers'\n")
      File.write(File.join(dir, "app/javascript/application.js"), "import \"controllers\"\n")
      File.write(
        File.join(dir, "app/javascript/controllers/index.js"),
        "import { application } from \"controllers/application\"\nimport { eagerLoadControllersFrom } from \"@hotwired/stimulus-loading\"\n"
      )
      yield dir
    end
  end

  def build_generator(destination_root, options = {})
    RecordingStudioAttachable::Generators::InstallGenerator.new([], options, destination_root: destination_root)
  end

  def test_mount_engine_uses_configured_mount_path
    generator = build_generator("/tmp", mount_path: "/studio/files")
    routes = []

    generator.stub(:route, ->(value) { routes << value }) do
      generator.mount_engine
    end

    assert_equal ['mount RecordingStudioAttachable::Engine, at: "/studio/files"'], routes
  end

  def test_verify_image_processor_succeeds_when_diagnostics_pass
    generator = build_generator("/tmp")
    result = RecordingStudioAttachable::ImageProcessorDiagnostics::Result.new(success: true, processor: :vips)

    RecordingStudioAttachable::ImageProcessorDiagnostics.stub(:call, result) do
      assert_nil generator.verify_image_processor
    end
  end

  def test_verify_image_processor_raises_actionable_error_when_diagnostics_fail
    generator = build_generator("/tmp")
    help = "Configured processor: vips\napt-get install libvips-tools\nThen rerun"
    result = RecordingStudioAttachable::ImageProcessorDiagnostics::Result.new(
      success: false,
      processor: :vips,
      error: "native libvips could not be loaded",
      installation_help: help
    )

    error = assert_raises(Thor::Error) do
      RecordingStudioAttachable::ImageProcessorDiagnostics.stub(:call, result) do
        generator.verify_image_processor
      end
    end

    assert_includes error.message, "Configured processor: vips"
    assert_includes error.message, "apt-get install libvips-tools"
    assert_includes error.message, "Then rerun"
  end

  def test_skip_image_processor_check_bypasses_diagnostics_and_warns
    generator = build_generator("/tmp", skip_image_processor_check: true)

    output, = capture_io do
      RecordingStudioAttachable::ImageProcessorDiagnostics.stub(:call, -> { flunk "diagnostics should not run" }) do
        generator.verify_image_processor
      end
    end

    assert_includes output, "Image processor validation was skipped"
    assert_includes output, "Image previews will not work"
  end

  def test_add_tailwind_source_injects_attachable_sources
    with_temp_app do |dir|
      css_path = File.join(dir, "app/assets/tailwind/application.css")
      File.write(css_path, "@import \"tailwindcss\";\n")

      generator = build_generator(dir)
      Rails.stub(:root, Pathname.new(dir)) { generator.add_tailwind_source }

      css = File.read(css_path)
      assert_includes css, "recording_studio_attachable/app/views/**/*.erb"
      assert_includes css, "flat_pack/app/components"
    end
  end

  def test_add_importmap_entries_appends_engine_pin_and_javascript_wiring
    with_temp_app do |dir|
      generator = build_generator(dir)
      Rails.stub(:root, Pathname.new(dir)) do
        generator.add_importmap_entries
        generator.add_importmap_entries
      end

      importmap = File.read(File.join(dir, "config/importmap.rb"))
      application_js = File.read(File.join(dir, "app/javascript/application.js"))
      controllers_index = File.read(File.join(dir, "app/javascript/controllers/index.js"))

      assert_includes importmap, "@rails/activestorage"
      assert_includes importmap, "controllers/recording_studio_attachable"
      assert_includes importmap, 'pin "recording_studio_attachable/tiptap/attachment_image_addon"'
      assert_includes importmap, "RecordingStudioAttachable::Engine.root"
      assert_includes importmap, 'to: "controllers/recording_studio_attachable"'
      assert_includes application_js, "import * as ActiveStorage from \"@rails/activestorage\"\nActiveStorage.start()\n"
      assert_includes application_js, 'import "recording_studio_attachable/tiptap/attachment_image_addon"'
      assert_includes controllers_index, "eagerLoadControllersFrom(\"controllers/recording_studio_attachable\", application)\n"
      assert_equal 1, importmap.scan("@rails/activestorage").size
      assert_equal 1, application_js.scan("ActiveStorage.start()").size
      assert_equal 1, controllers_index.scan("controllers/recording_studio_attachable").size
    end
  end

  def test_add_importmap_entries_completes_partial_wiring_without_duplicates
    with_temp_app do |dir|
      importmap_path = File.join(dir, "config/importmap.rb")
      File.write(importmap_path, %(pin "@rails/activestorage", to: "activestorage.esm.js"\n))
      generator = build_generator(dir)

      Rails.stub(:root, Pathname.new(dir)) { generator.add_importmap_entries }

      importmap = File.read(importmap_path)
      assert_equal 1, importmap.scan("@rails/activestorage").size
      assert_includes importmap, "controllers/recording_studio_attachable"
      assert_includes importmap, "recording_studio_attachable/tiptap/attachment_image_addon"
    end
  end

  def test_initializer_template_defaults_to_blank_layout_and_mentions_override
    initializer_template = File.read(
      File.expand_path(
        "../lib/generators/recording_studio_attachable/install/templates/recording_studio_attachable_initializer.rb",
        __dir__
      )
    )

    assert_includes initializer_template, "config.layout = :blank"
    assert_includes initializer_template, 'host app layout like "application"'
  end

  def test_install_docs_describe_recording_studio_3_hierarchy_setup
    install_docs = File.read(
      File.expand_path(
        "../lib/generators/recording_studio_attachable/install/templates/INSTALL.md",
        __dir__
      )
    )

    assert_includes install_docs, "Recording Studio 3.0.0+"
    assert_includes install_docs, "recording_studio_recordable"
    assert_includes install_docs, "allowed_parent_types"
    assert_includes install_docs, "RecordingStudioAttachable::Attachment"
    assert_includes install_docs, ":attachable"
    assert_not_includes install_docs, "Register `RecordingStudioAttachable::Attachment` in `RecordingStudio.configure`"
  end
end
