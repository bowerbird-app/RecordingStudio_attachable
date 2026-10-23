# frozen_string_literal: true

module RecordingStudioAttachable
  module ProviderConnect
    module_function

    def payload(provider:, recording:, context:, **flags)
      {
        provider_key: provider.key.to_s,
        launcher: provider.launcher,
        import_url: flags[:import_url],
        needs_auth: flags.fetch(:needs_auth),
        reconnect: flags.fetch(:reconnect),
        connect: provider.connect_payload(recording: recording, context: context)
      }.compact
    end
  end
end
