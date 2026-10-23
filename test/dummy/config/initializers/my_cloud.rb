# frozen_string_literal: true

require "stringio"

RecordingStudioAttachable.configure do |config|
  config.register_upload_provider(
    :my_cloud,
    label: "My Cloud",
    icon: "cloud",
    strategy: :client_picker,
    launcher: "my_cloud",
    launcher_module: "my_cloud/picker_launcher",
    url: ->(route_helpers:, recording:) { route_helpers.my_cloud.recording_bootstrap_path(recording, format: :json) },
    bootstrap_url: ->(route_helpers:, recording:) { route_helpers.my_cloud.recording_bootstrap_path(recording, format: :json) },
    import_url: ->(route_helpers:, recording:) { route_helpers.my_cloud.recording_imports_path(recording, format: :json) },
    allowed_payload_keys: %w[id],
    remote_importer: lambda do |parent_recording:, attachments:, actor: nil, impersonator: nil, **|
      raise RecordingStudioAttachable::ReconnectRequired, "reconnect" if MyCloud.reconnect_required?

      RecordingStudioAttachable::Services::ImportRemoteFiles.call(
        parent_recording: parent_recording,
        provider_key: :my_cloud,
        actor: actor,
        impersonator: impersonator,
        payloads: attachments.map do |payload|
          id = payload.fetch(:provider_payload).fetch("id")
          file = MyCloud::FILES.find { |entry| entry["id"] == id } || MyCloud::FILES.first
          {
            download: -> { { io: StringIO.new(MyCloud::CLOUD_PNG), filename: file["name"], content_type: file["content_type"] } },
            filename: file["name"],
            content_type: file["content_type"],
            byte_size: MyCloud::CLOUD_PNG.bytesize,
            name: payload[:name].presence || file["name"],
            metadata: { external_id: file["id"], external_url: "https://cloud.test/#{file['id']}" }
          }
        end
      )
    end,
    connect: lambda do |recording:, context:|
      helpers = context.my_cloud
      {
        url: helpers.recording_connect_path(recording, popup: 1),
        method: "post",
        fields: { authenticity_token: context.provider_csrf_token },
        fallback_url: helpers.recording_connect_path(recording)
      }
    end
  )
end
