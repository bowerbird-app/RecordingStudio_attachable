# frozen_string_literal: true

module RecordingStudioAttachable
  # Routes still required when config.active_storage.draw_routes is false.
  # The URL helpers live in Rails' route file, so they are redrawn here.
  # Proxy routes and the anonymous direct_uploads route are not.
  module ActiveStorageRoutes
    DIRECT_UPLOADS_ROUTE = :rails_direct_uploads

    WARNING = "RecordingStudioAttachable: Rails draws the anonymous direct_uploads route " \
              "(POST /rails/active_storage/direct_uploads by default). Anyone can create a blob and " \
              "receive a signed id. Set config.active_storage.draw_routes = false, then redraw only the " \
              "signed blob redirect, the representation redirect, and Disk show and update. " \
              "Set config.warn_on_active_storage_routes = false to silence this warning."

    REDIRECTS = [
      [:get, "/blobs/redirect/:signed_id/*filename", "active_storage/blobs/redirect#show", :rails_service_blob],
      [
        :get,
        "/representations/redirect/:signed_blob_id/:variation_key/*filename",
        "active_storage/representations/redirect#show",
        :rails_blob_representation
      ]
    ].freeze

    DISK = [
      [:get, "/disk/:encoded_key/*filename", "active_storage/disk#show", :rails_disk_service],
      [:put, "/disk/:encoded_token", "active_storage/disk#update", :update_rails_disk_service]
    ].freeze

    URL_HELPERS = %i[rails_representation rails_blob].freeze

    POLYMORPHIC_MODELS = %w[
      ActiveStorage::Variant
      ActiveStorage::VariantWithRecord
      ActiveStorage::Preview
      ActiveStorage::Blob
    ].freeze

    class << self
      def draw(mapper, app: Rails.application)
        definitions = REDIRECTS.dup
        definitions.concat(DISK) if disk?(app)
        draw_http(mapper, definitions)
        draw_direct_helpers(mapper)
        draw_resolvers(mapper)
      end

      def warn_if_exposed
        return unless RecordingStudioAttachable.configuration.warn_on_active_storage_routes
        return unless direct_uploads_drawn?

        Rails.logger&.warn(WARNING)
      end

      def direct_uploads_drawn?(routes = Rails.application.routes)
        routes.named_routes.names.include?(DIRECT_UPLOADS_ROUTE)
      end

      def disk?(app = Rails.application)
        path = app.root.join("config/storage.yml")
        configs = ActiveSupport::ConfigurationFile.parse(path)
        configs.dig(app.config.active_storage.service.to_s, "service") == "Disk"
      end

      def signed_redirect(helpers, model, options)
        expires_in = options.delete(:expires_in) { ActiveStorage.urls_expire_in }
        expires_at = options.delete(:expires_at)
        source = model.respond_to?(:signed_id) ? model : model.blob
        signed_id = source.signed_id(expires_in: expires_in, expires_at: expires_at)
        if model.respond_to?(:signed_id)
          helpers.route_for(:rails_service_blob, signed_id, model.filename, options)
        else
          helpers.route_for(:rails_blob_representation, signed_id, model.variation.key, model.blob.filename, options)
        end
      end

      private

      def draw_http(mapper, definitions)
        mapper.instance_exec(definitions) do |routes|
          scope ActiveStorage.routes_prefix do
            routes.each do |verb, path, target, name|
              public_send(verb, path, to: target, as: name)
            end
          end
        end
      end

      def draw_direct_helpers(mapper)
        URL_HELPERS.each do |name|
          mapper.direct(name) do |model, options|
            route_for(ActiveStorage.resolve_model_to_route, model, options)
          end
        end
        mapper.direct(:rails_storage_redirect) do |model, options|
          RecordingStudioAttachable::ActiveStorageRoutes.signed_redirect(self, model, options)
        end
      end

      def draw_resolvers(mapper)
        POLYMORPHIC_MODELS.each do |model_name|
          mapper.resolve(model_name) do |record, options|
            route_for(ActiveStorage.resolve_model_to_route, record, options)
          end
        end
        mapper.resolve("ActiveStorage::Attachment") do |attachment, options|
          route_for(ActiveStorage.resolve_model_to_route, attachment.blob, options)
        end
      end
    end
  end
end
