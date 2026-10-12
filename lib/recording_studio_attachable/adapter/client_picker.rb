# frozen_string_literal: true

module RecordingStudioAttachable
  module Adapter
    module ClientPicker
      module_function

      def provider_options(**attrs)
        picker_urls(attrs).merge(
          label: attrs.fetch(:label),
          icon: "cloud",
          strategy: :client_picker,
          launcher: attrs.fetch(:launcher),
          launcher_module: attrs.fetch(:launcher_module),
          remote_importer: attrs.fetch(:remote_importer),
          allowed_payload_keys: attrs.fetch(:allowed_payload_keys)
        )
      end

      def import_from_session(context:, attachments:, session_token_class:, import_class:, **import_args)
        import_class.call(
          file_ids: Selection.from_attachments(attachments),
          access_token: session_token_class.fetch(session: context.session),
          **import_args
        )
      end

      def picker_urls(attrs)
        path = attrs.fetch(:bootstrap_path)
        { url: path, bootstrap_url: path, import_url: attrs.fetch(:import_path) }
      end
    end
  end
end
