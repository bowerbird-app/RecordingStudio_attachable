# frozen_string_literal: true

require "rails/generators"

module RecordingStudioAttachable
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Installs RecordingStudioAttachable into your application"

      class_option :mount_path,
                   type: :string,
                   default: "/recording_studio_attachable",
                   desc: "Route prefix used when mounting the engine"

      def mount_engine
        route %(mount RecordingStudioAttachable::Engine, at: "#{options[:mount_path]}")
      end

      def copy_initializer
        template "recording_studio_attachable_initializer.rb", "config/initializers/recording_studio_attachable.rb"
      end

      def add_tailwind_source
        tailwind_css_path = Rails.root.join("app/assets/tailwind/application.css")
        return unless File.exist?(tailwind_css_path)

        tailwind_content = File.read(tailwind_css_path)
        missing_lines = tailwind_source_lines.reject { |line| tailwind_content.include?(line) }
        return if missing_lines.empty?

        inject_into_file tailwind_css_path, after: "@import \"tailwindcss\";\n" do
          ["", *missing_lines, ""].join("\n")
        end
      end

      def add_importmap_entries
        importmap_path = Rails.root.join("config/importmap.rb")
        return unless File.exist?(importmap_path)

        append_to_file importmap_path, <<~RUBY unless File.read(importmap_path).include?("controllers/recording_studio_attachable")

          pin "@rails/activestorage", to: "activestorage.esm.js"
          pin_all_from RecordingStudioAttachable::Engine.root.join("app/javascript/controllers/recording_studio_attachable"),
            under: "controllers/recording_studio_attachable",
            to: "controllers/recording_studio_attachable"
        RUBY

        wire_javascript_entrypoints
      end

      def show_readme
        readme "INSTALL.md" if behavior == :invoke
      end

      private

      def tailwind_source_lines
        [
          '@source "../../vendor/bundle/**/recording_studio_attachable/app/views/**/*.erb";',
          '@source "../../vendor/bundle/**/flat_pack/app/components";'
        ]
      end

      def wire_javascript_entrypoints
        application_js_path = Rails.root.join("app/javascript/application.js")
        if File.exist?(application_js_path)
          application_js = File.read(application_js_path)
          unless active_storage_wired?(application_js)
            append_to_file application_js_path, <<~JS
              import * as ActiveStorage from "@rails/activestorage"
              ActiveStorage.start()
            JS
          end
        end

        controllers_index_path = Rails.root.join("app/javascript/controllers/index.js")
        return unless File.exist?(controllers_index_path)

        controllers_index = File.read(controllers_index_path)
        return if attachable_controllers_wired?(controllers_index)

        append_to_file controllers_index_path, "eagerLoadControllersFrom(\"controllers/recording_studio_attachable\", application)\n"
      end

      def active_storage_wired?(application_js)
        normalized = application_js.gsub(/\s+/, " ")
        normalized.match?(%r{@rails/activestorage}) && normalized.match?(/ActiveStorage\.start\(\)/)
      end

      def attachable_controllers_wired?(controllers_index)
        controllers_index.match?(%r{controllers/recording_studio_attachable})
      end
    end
  end
end
