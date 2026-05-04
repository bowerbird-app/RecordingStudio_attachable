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

  def test_add_tailwind_source_injects_attachable_sources
    with_temp_app do |dir|
      css_path = File.join(dir, "app/assets/tailwind/application.css")
      File.write(css_path, "@import \"tailwindcss\";\n")

      generator = build_generator(dir)
      Rails.stub(:root, Pathname.new(dir)) { generator.add_tailwind_source }

      css = File.read(css_path)
      assert_includes css, "recording_studio_attachable/app/views/**/*.erb"
      assert_includes css, "flat_pack/app/components/**/*.{rb,erb}"
    end
  end

  def test_add_importmap_entries_appends_engine_pin_and_javascript_wiring
    with_temp_app do |dir|
      generator = build_generator(dir)
      Rails.stub(:root, Pathname.new(dir)) { generator.add_importmap_entries }

      importmap = File.read(File.join(dir, "config/importmap.rb"))
      application_js = File.read(File.join(dir, "app/javascript/application.js"))
      controllers_index = File.read(File.join(dir, "app/javascript/controllers/index.js"))

      assert_includes importmap, "@rails/activestorage"
      assert_includes importmap, "controllers/recording_studio_attachable"
      assert_includes importmap, "RecordingStudioAttachable::Engine.root"
      assert_includes application_js, "@rails/activestorage"
      assert_includes application_js, "ActiveStorage.start()"
      assert_includes controllers_index, 'eagerLoadControllersFrom("controllers/recording_studio_attachable", application)'
    end
  end
end
