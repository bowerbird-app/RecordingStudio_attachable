# frozen_string_literal: true

require "test_helper"

class ProviderConnectTest < Minitest::Test
  FakeRecording = Struct.new(:id)
  FakeContext = Struct.new(:provider_csrf_token)

  def test_payload_uses_generic_connect_shape
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :my_cloud,
      label: "My Cloud",
      url: "/bootstrap",
      launcher: "my_cloud",
      connect: lambda { |recording:, context:|
        {
          url: "/my_cloud/recordings/#{recording.id}/connect",
          method: "POST",
          fields: { authenticity_token: context.provider_csrf_token },
          fallback_url: "/my_cloud/recordings/#{recording.id}/connect"
        }
      }
    )

    payload = RecordingStudioAttachable::ProviderConnect.payload(
      provider: provider,
      recording: FakeRecording.new("rec-1"),
      context: FakeContext.new("csrf"),
      needs_auth: true,
      reconnect: false,
      import_url: "/imports.json"
    )

    assert_equal "my_cloud", payload[:provider_key]
    assert_equal "my_cloud", payload[:launcher]
    assert_equal "/imports.json", payload[:import_url]
    assert payload[:needs_auth]
    refute payload[:reconnect]
    assert_equal "post", payload[:connect][:method]
    assert_equal "csrf", payload[:connect][:fields][:authenticity_token]
    refute payload[:connect].key?(:client_id)
  end

  def test_import_remote_attachments_maps_reconnect_errors
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :my_cloud,
      label: "My Cloud",
      url: "/bootstrap",
      remote_importer: ->(**) { raise RecordingStudioAttachable::ReconnectRequired, "expired" },
      connect: ->(recording:, **) { { url: "/connect/#{recording.id}", method: "post", fields: {} } }
    )

    result = provider.import_remote_attachments(
      parent_recording: FakeRecording.new("rec-1"),
      attachments: [{ provider_payload: { id: "file-1" } }],
      context: FakeContext.new("csrf")
    )

    refute result.success?
    assert_equal "Reconnect My Cloud to continue", result.error
    assert_equal "/connect/rec-1", result.errors[:url]
  end

  def test_reconnect_error_proc_maps_provider_errors
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :my_cloud,
      label: "My Cloud",
      url: "/bootstrap",
      remote_importer: ->(**) { raise KeyError, "missing token" },
      reconnect_error: ->(error) { error.is_a?(KeyError) },
      connect: ->(**) { { url: "/connect", fields: { authenticity_token: "t" } } }
    )

    result = provider.import_remote_attachments(
      parent_recording: FakeRecording.new("rec-1"),
      attachments: [],
      context: FakeContext.new("csrf")
    )

    refute result.success?
    assert_equal "/connect", result.errors[:url]
  end
end
