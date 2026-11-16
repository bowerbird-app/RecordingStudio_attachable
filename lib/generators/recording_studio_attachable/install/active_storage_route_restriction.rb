# frozen_string_literal: true

module RecordingStudioAttachable
  module Generators
    # Idempotent edits for --restrict-active-storage-routes.
    class ActiveStorageRouteRestriction
      APPLICATION_MARKER = "ActiveStorage.draw_routes = false"
      ROUTES_MARKER = "RecordingStudioAttachable::ActiveStorageRoutes.draw"

      def self.apply(generator, destination_root)
        new(generator, destination_root).apply
      end

      def initialize(generator, destination_root)
        @generator = generator
        @destination_root = destination_root
      end

      def apply
        insert_application
        insert_routes
      end

      private

      def insert_application
        return if application_body.nil? || application_body.include?(APPLICATION_MARKER)

        @generator.insert_into_file application_path, application_snippet, after: /class [A-Z]\w* < Rails::Application\n/
      end

      def insert_routes
        return if routes_body.nil? || routes_body.include?(ROUTES_MARKER)

        @generator.insert_into_file routes_path, routes_snippet, after: /\.routes\.draw do\n/
      end

      def application_body
        read(application_path)
      end

      def routes_body
        read(routes_path)
      end

      def read(path)
        full_path = File.join(@destination_root, path)
        return unless File.exist?(full_path)

        File.read(full_path)
      end

      def application_path
        "config/application.rb"
      end

      def routes_path
        "config/routes.rb"
      end

      def application_snippet
        <<~RUBY.indent(4)
          # Devise reloads routes from before_eager_load, before Active Storage
          # copies this config in after_initialize. Set the module attribute here.
          # An initializer before-edge reshuffles boot and skips recordable registration.
          config.active_storage.draw_routes = false
          ActiveStorage.draw_routes = false

        RUBY
      end

      def routes_snippet
        <<~RUBY.indent(2)
          # Signed blob redirect, representation redirect, and Disk show and update.
          # The anonymous direct_uploads route stays undrawn.
          #{ROUTES_MARKER}(self)

        RUBY
      end
    end
  end
end
