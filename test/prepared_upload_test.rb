# frozen_string_literal: true

require "test_helper"
require "net/http"
require_relative "../app/services/recording_studio_attachable/services/application_service"
require_relative "../app/services/recording_studio_attachable/services/record_attachment_upload"
require_relative "../app/services/recording_studio_attachable/services/replace_attachment_file"

class PreparedUploadTest < Minitest::Test
  PNG = UploadBlobBytes::PNG
  SVG = '<svg xmlns="http://www.w3.org/2000/svg"></svg>'
  ZIP = "PK\x03\x04not-a-zip-body"
  Auth = RecordingStudioAttachable::Authorization

  class ClosedOwner
    def attachable_available_for?(**)
      false
    end
  end

  RecordingDouble = Struct.new(
    :id, :recordable_type, :root_recording, :parent_recording_id, :trashed_at, :recordable, keyword_init: true
  )

  class PendingScope
    attr_reader :count

    def initialize(count)
      @count = count
    end

    def where(*)
      self
    end
  end

  def setup
    @original = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    RecordingStudioAttachable.configuration.authorize_with = ->(**) { true }
    pin_capability_options!
    @blob_methods = install_blob_methods
    ensure_attachment_class!
    ensure_api_errors!
  end

  def teardown
    restore_capability_options!
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original)
    remove_blob_methods(@blob_methods)
  end

  def test_fetch_upload_returns_a_signed_id_that_attach_and_replace_accept
    recording = recording_double("parent-1")
    actor = actor_double
    blob = ticket_blob(recording, actor)
    created = nil

    with_access do
      with_pending(0) do
        with_http(PNG, content_type: "image/png") do
          ActiveStorage::Blob.stub(:create_and_upload!, lambda { |**attributes|
            created = attributes
            blob.metadata = attributes[:metadata]
            blob.content_type = attributes[:content_type]
            blob.filename = attributes[:filename]
            blob
          }) do
            ticket = RecordingStudioAttachable.fetch_upload(
              recording: recording,
              actor: actor,
              url: "https://files.example.test/photos/door.png"
            )

            assert_equal "signed-attachable_upload", ticket[:signed_blob_id]
            assert_equal "https://uploads.example.test/put", ticket.dig(:upload, :url)
            assert_equal "image/png", ticket.dig(:upload, :headers, "Content-Type")
            assert ticket[:expires_at].present?
            assert_equal "door.png", created[:filename]
            assert_equal "image/png", created[:content_type]
            assert_equal false, created[:identify]
            assert_equal "1", created.dig(:metadata, RecordingStudioAttachable::DirectUpload::TAG)
            assert_equal "parent-1", created.dig(:metadata, "parent_recording_id")
            assert_equal actor.id, created.dig(:metadata, "actor_id")
            assert_services_accept(ticket[:signed_blob_id], recording, actor, blob)
          end
        end
      end
    end
  end

  def test_inline_upload_accepts_raw_base64_and_a_data_uri
    recording = recording_double("parent-1")
    actor = actor_double
    blob = ticket_blob(recording, actor)
    encoded = Base64.strict_encode64(PNG)
    names = []

    with_access do
      with_pending(0) do
        ActiveStorage::Blob.stub(:create_and_upload!, lambda { |**attributes|
          names << attributes[:filename]
          blob.metadata = attributes[:metadata]
          blob.content_type = attributes[:content_type]
          blob.filename = attributes[:filename]
          blob
        }) do
          raw = RecordingStudioAttachable.inline_upload(
            recording: recording, actor: actor, data: encoded, filename: "raw.png"
          )
          uri = RecordingStudioAttachable.inline_upload(
            recording: recording,
            actor: actor,
            data: "data:image/png;base64,#{encoded}",
            filename: "uri.png"
          )

          assert_equal "signed-attachable_upload", raw[:signed_blob_id]
          assert_equal raw[:signed_blob_id], uri[:signed_blob_id]
          assert_equal %w[raw.png uri.png], names
          assert_services_accept(raw[:signed_blob_id], recording, actor, blob)
        end
      end
    end
  end

  def test_fetch_upload_refuses_a_private_address
    refused("https://files.example.test/door.png", addresses: ["10.1.2.3"]) do |error|
      assert_includes error.message, "private address"
    end
  end

  def test_fetch_upload_rejects_a_url_that_is_not_a_public_https_address
    recording = recording_double("parent-1")
    actor = actor_double
    handler = RecordingStudioAttachable::Api::AttachmentActions::CreateUpload
    urls = [
      "/mnt/data/photo.jpg",
      "/mnt/data/images(1).jpeg",
      "file:///mnt/data/photo.jpg",
      "http://files.example.test/door.png",
      "not a url",
      "https:///photo.jpg"
    ]

    urls.each do |url|
      with_access do
        with_pending(0) do
          with_http(PNG, content_type: "image/png", fail_if_called: true) do
            error = assert_raises(ArgumentError, url) do
              RecordingStudioAttachable.fetch_upload(recording: recording, actor: actor, url: url)
            end
            assert_includes error.message, "public https://", url
            assert_includes error.message, "base64 data with filename", url
            assert_includes error.message, "send file", url
            refute_includes error.message, url, url

            api_error = assert_raises(RecordingStudioApi::InvalidActionInputError, url) do
              handler.call(context(recording, actor, url: url))
            end
            assert_equal error.message, api_error.message
            refute_kind_of RecordingStudioAttachable::SafeRemoteFetch::Error, api_error
          end
        end
      end
    end
  end

  def test_fetch_upload_refuses_a_host_outside_the_allowlist
    RecordingStudioAttachable.configuration.import_allowed_hosts = ["cdn.example.com"]

    refused("https://files.example.test/door.png") do |error|
      assert_equal RecordingStudioAttachable::SafeRemoteFetch::HostGuard::HOST_NOT_ALLOWED, error.message
    end
  end

  def test_fetch_upload_refuses_when_imports_are_off
    RecordingStudioAttachable.configuration.import_allowed_hosts = :none

    refused("https://files.example.test/door.png") do |error|
      assert_equal RecordingStudioAttachable::SafeRemoteFetch::HostGuard::IMPORTS_OFF, error.message
    end
  end

  def test_fetch_upload_refuses_an_oversize_download
    RecordingStudioAttachable.configuration.max_file_size = 4

    with_access do
      with_pending(0) do
        with_http(PNG, content_type: "image/png") do
          error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
            RecordingStudioAttachable.fetch_upload(recording: recording_double("parent-1"), actor: actor_double, url: "https://files.example.test/door.png")
          end
          assert_includes error.message, "maximum file size"
        end
      end
    end
  end

  def test_fetch_upload_refuses_a_disallowed_type
    refused_body(ZIP, content_type: "application/zip", url: "https://files.example.test/virus.zip") do |error|
      assert_includes error.message, "not allowed"
    end
  end

  def test_fetch_upload_refuses_svg_under_an_image_wildcard
    refused_body(SVG, content_type: "image/svg+xml", url: "https://files.example.test/icon.svg") do |error|
      assert_includes error.message, "not allowed"
    end
  end

  def test_fetch_upload_refuses_when_the_pending_limit_is_hit
    RecordingStudioAttachable.configuration.pending_upload_limit = 1

    with_access do
      with_pending(1) do
        with_http(PNG, content_type: "image/png", fail_if_called: true) do
          error = assert_raises(ArgumentError) do
            RecordingStudioAttachable.fetch_upload(recording: recording_double("parent-1"), actor: actor_double, url: "https://files.example.test/door.png")
          end
          assert_includes error.message, "pending"
        end
      end
    end
  end

  def test_fetch_upload_refuses_without_the_edit_role
    RecordingStudioAttachable.configuration.authorize_with = ->(**) { false }

    with_access do
      with_http(PNG, content_type: "image/png", fail_if_called: true) do
        error = assert_raises(Auth::NotAuthorizedError) do
          RecordingStudioAttachable.fetch_upload(recording: recording_double("parent-1"), actor: actor_double, url: "https://files.example.test/door.png")
        end
        assert_equal Auth::NotAuthorizedError, error.class
      end
    end
  end

  def test_fetch_upload_refuses_a_trashed_owner
    recording = recording_double("child-1", parent_recording_id: "root-1", trashed_at: Time.now)

    with_access do
      with_http(PNG, content_type: "image/png", fail_if_called: true) do
        error = assert_raises(Auth::OwnerUnavailableError) do
          RecordingStudioAttachable.fetch_upload(recording: recording, actor: actor_double, url: "https://files.example.test/door.png")
        end
        assert_includes error.message, "Not authorized"
      end
    end
  end

  def test_fetch_upload_refuses_an_unavailable_owner
    recording = recording_double(
      "parent-1",
      recordable_type: "PreparedUploadTest::ClosedOwner",
      recordable: ClosedOwner.new
    )

    with_access do
      with_http(PNG, content_type: "image/png", fail_if_called: true) do
        assert_raises(Auth::OwnerUnavailableError) do
          RecordingStudioAttachable.fetch_upload(recording: recording, actor: actor_double, url: "https://files.example.test/door.png")
        end
      end
    end
  end

  def test_inline_upload_refuses_input_over_the_inline_cap
    RecordingStudioAttachable.configuration.inline_upload_max_bytes = 8

    with_access do
      with_pending(0) do
        error = assert_raises(ArgumentError) do
          RecordingStudioAttachable.inline_upload(
            recording: recording_double("parent-1"),
            actor: actor_double,
            data: Base64.strict_encode64(PNG),
            filename: "door.png"
          )
        end
        assert_includes error.message, "8 bytes"
        assert_includes error.message, "data uploads can be up to"
        refute_includes error.message, "inline_upload_max_bytes"
      end
    end
  end

  def test_inline_upload_states_the_megabyte_limit_and_the_record_cap
    over_inline = assert_raises(ArgumentError) do
      upload_inline(data: base64_for_megabytes(11.2))
    end
    assert_includes over_inline.message, "11.2 MB"
    assert_includes over_inline.message, "data uploads can be up to 2 MB"
    assert_includes over_inline.message, "public https url"
    refute_includes over_inline.message, "inline_upload_max_bytes"

    RecordingStudioAttachable.configuration.max_file_size = 1.megabyte
    over_record = assert_raises(ArgumentError) do
      upload_inline(data: base64_for_megabytes(1.5))
    end
    assert_includes over_record.message, "1.5 MB"
    assert_includes over_record.message, "this record accepts files up to 1 MB"
    refute_includes over_record.message, "2 MB"
    refute_includes over_record.message, "inline_upload_max_bytes"
  end

  def test_inline_upload_refuses_bad_base64
    with_access do
      with_pending(0) do
        ["@@@@", "data:text/plain,hello"].each do |data|
          error = assert_raises(ArgumentError) do
            RecordingStudioAttachable.inline_upload(
              recording: recording_double("parent-1"), actor: actor_double, data: data, filename: "door.png"
            )
          end
          assert_equal RecordingStudioAttachable::PreparedUpload::BAD_BASE64, error.message
        end
      end
    end
  end

  def test_inline_upload_refuses_a_disallowed_type
    with_access do
      with_pending(0) do
        error = assert_raises(ArgumentError) do
          RecordingStudioAttachable.inline_upload(
            recording: recording_double("parent-1"),
            actor: actor_double,
            data: Base64.strict_encode64(ZIP),
            filename: "virus.zip"
          )
        end
        assert_includes error.message, "not allowed"
      end
    end
  end

  def test_inline_upload_refuses_without_the_edit_role
    RecordingStudioAttachable.configuration.authorize_with = ->(**) { false }

    with_access do
      error = assert_raises(Auth::NotAuthorizedError) do
        RecordingStudioAttachable.inline_upload(
          recording: recording_double("parent-1"),
          actor: actor_double,
          data: Base64.strict_encode64(PNG),
          filename: "door.png"
        )
      end
      assert_equal Auth::NotAuthorizedError, error.class
    end
  end

  def test_create_upload_accepts_url_and_rejects_both_sources_or_a_partial_direct_upload
    recording = recording_double("parent-1")
    actor = actor_double
    blob = ticket_blob(recording, actor)
    handler = RecordingStudioAttachable::Api::AttachmentActions::CreateUpload

    with_access do
      with_pending(0) do
        with_http(PNG, content_type: "image/png") do
          ActiveStorage::Blob.stub(:create_and_upload!, lambda { |**attributes|
            blob.metadata = attributes[:metadata]
            blob.content_type = attributes[:content_type]
            blob.filename = attributes[:filename]
            blob
          }) do
            ticket = handler.call(context(recording, actor, url: "https://files.example.test/door.png"))
            assert_equal "signed-attachable_upload", ticket[:signed_blob_id]
          end
        end
      end

      both = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        handler.call(context(recording, actor, url: "https://files.example.test/door.png", data: "aaaa"))
      end
      assert_includes both.message, "only one"

      [{}, { filename: "door.png" }].each do |params|
        missing = assert_raises(RecordingStudioApi::InvalidActionInputError) do
          handler.call(context(recording, actor, params))
        end
        assert_includes missing.message, "filename, byte_size, checksum, and content_type"
        assert_includes missing.message, "direct upload"
        assert_includes missing.message, "or send url"
        assert_includes missing.message, "data and filename"
        assert_includes missing.message, "or send file"
      end

      path = "/mnt/data/images(1).jpeg"
      with_pending(0) do
        sandbox = assert_raises(RecordingStudioApi::InvalidActionInputError) do
          handler.call(context(recording, actor, data: path, filename: "images(1).jpeg"))
        end
        assert_includes sandbox.message, "send file"
        assert_includes sandbox.message, "https url"
        refute_includes sandbox.message, path
      end
    end
  end

  def test_file_upload_returns_a_signed_id_that_attach_and_replace_accept
    recording = recording_double("parent-1")
    actor = actor_double
    blob = ticket_blob(recording, actor)
    secret = "https://files.example.test/secret-token/door.png?sig=keep-me"
    created = nil

    with_access do
      with_pending(0) do
        with_http(PNG, content_type: "application/octet-stream") do
          ActiveStorage::Blob.stub(:create_and_upload!, lambda { |**attributes|
            created = attributes
            blob.metadata = attributes[:metadata]
            blob.content_type = attributes[:content_type]
            blob.filename = attributes[:filename]
            blob
          }) do
            ticket = RecordingStudioAttachable::PreparedUpload.fetch(
              recording: recording,
              actor: actor,
              file: {
                download_url: secret,
                file_id: "file_123",
                mime_type: "image/jpeg",
                file_name: "images(1).jpeg"
              }
            )

            assert_equal "signed-attachable_upload", ticket[:signed_blob_id]
            assert_equal "images(1).jpeg", created[:filename]
            assert_equal "image/png", created[:content_type]
            assert_services_accept(ticket[:signed_blob_id], recording, actor, blob)
            refute_includes ticket.to_s, secret
            refute_includes created[:metadata].to_s, secret
            refute_includes created[:filename].to_s, secret
          end
        end
      end
    end
  end

  def test_file_upload_refuses_a_private_host_http_oversize_wrong_type_and_no_edit_role
    secret = "https://files.example.test/secret-token/door.png?sig=keep-me"
    recording = recording_double("parent-1")
    actor = actor_double
    file = { download_url: secret, file_id: "file_123", file_name: "door.png" }

    with_access do
      with_pending(0) do
        with_http(PNG, content_type: "image/png", addresses: ["10.1.2.3"], fail_if_called: true) do
          error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
            RecordingStudioAttachable::PreparedUpload.fetch(recording: recording, actor: actor, file: file)
          end
          assert_includes error.message, "could not be downloaded"
          assert_includes error.message, "private address"
          refute_includes error.message, secret
          assert_nil error.cause
        end
      end
    end

    http_secret = "http://files.example.test/secret-token/door.png?sig=keep-me"
    with_access do
      with_pending(0) do
        with_http(PNG, content_type: "image/png", fail_if_called: true) do
          error = assert_raises(ArgumentError) do
            RecordingStudioAttachable::PreparedUpload.fetch(
              recording: recording, actor: actor, file: file.merge(download_url: http_secret)
            )
          end
          assert_includes error.message, "https"
          refute_includes error.message, http_secret
        end
      end
    end

    RecordingStudioAttachable.configuration.max_file_size = 4
    with_access do
      with_pending(0) do
        with_http(PNG, content_type: "image/png") do
          error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
            RecordingStudioAttachable::PreparedUpload.fetch(recording: recording, actor: actor, file: file)
          end
          assert_includes error.message, "could not be downloaded"
          assert_includes error.message, "maximum file size"
          refute_includes error.message, secret
        end
      end
    end
    RecordingStudioAttachable.configuration.max_file_size = 25.megabytes

    with_access do
      with_pending(0) do
        with_http(ZIP, content_type: "application/zip") do
          ActiveStorage::Blob.stub(:create_and_upload!, ->(**) { flunk "created a blob" }) do
            error = assert_raises(ArgumentError) do
              RecordingStudioAttachable::PreparedUpload.fetch(
                recording: recording, actor: actor, file: file.merge(file_name: "virus.zip", mime_type: "image/png")
              )
            end
            assert_includes error.message, "not allowed"
            refute_includes error.message, secret
          end
        end
      end
    end

    RecordingStudioAttachable.configuration.authorize_with = ->(**) { false }
    with_access do
      with_http(PNG, content_type: "image/png", fail_if_called: true) do
        error = assert_raises(Auth::NotAuthorizedError) do
          RecordingStudioAttachable::PreparedUpload.fetch(recording: recording, actor: actor, file: file)
        end
        assert_equal Auth::NotAuthorizedError, error.class
        refute_includes error.message, secret
      end
    end
  end

  def test_create_upload_refuses_mixed_sources_and_keeps_the_download_url_out_of_the_reply
    recording = recording_double("parent-1")
    actor = actor_double
    handler = RecordingStudioAttachable::Api::AttachmentActions::CreateUpload
    secret = "https://files.example.test/secret-token/door.png?sig=keep-me"
    file = { download_url: secret, file_id: "file_123", mime_type: "image/png", file_name: "door.png" }

    with_access do
      [
        { url: "https://files.example.test/door.png", file: file },
        { data: "aaaa", file: file, filename: "door.png" },
        { url: "https://files.example.test/door.png", data: "aaaa", file: file },
        { filename: "door.png", byte_size: 12, checksum: "abc", content_type: "image/png", file: file }
      ].each do |params|
        error = assert_raises(RecordingStudioApi::InvalidActionInputError) do
          handler.call(context(recording, actor, params))
        end
        assert_includes error.message, "only one"
        refute_includes error.message, secret
      end
    end
  end

  private

  def refused(url, addresses: ["8.8.8.8"])
    with_access do
      with_pending(0) do
        with_http(PNG, content_type: "image/png", addresses: addresses, fail_if_called: true) do
          error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
            RecordingStudioAttachable.fetch_upload(recording: recording_double("parent-1"), actor: actor_double, url: url)
          end
          yield error
        end
      end
    end
  end

  def refused_body(body, content_type:, url:)
    with_access do
      with_pending(0) do
        with_http(body, content_type: content_type) do
          ActiveStorage::Blob.stub(:create_and_upload!, ->(**) { flunk "created a blob" }) do
            error = assert_raises(ArgumentError) do
              RecordingStudioAttachable.fetch_upload(recording: recording_double("parent-1"), actor: actor_double, url: url)
            end
            yield error
          end
        end
      end
    end
  end

  def assert_services_accept(signed_id, recording, actor, blob)
    attachment = Struct.new(:id, :name, :description, :caption, :credit, :alt_text, :attachment_kind,
                            :original_filename, :content_type, :byte_size).new(
                              "attachment-1", "Door", nil, nil, nil, nil, "image", "door.png", "image/png", PNG.bytesize
                            )
    child = Struct.new(:id, :recordable).new("child-1", attachment)
    event = Struct.new(:recording).new(child)
    attachment_recording = RecordingDouble.new(
      id: "attachment-recording",
      recordable_type: "RecordingStudioAttachable::Attachment",
      root_recording: recording.root_recording,
      recordable: attachment
    )
    attachment_recording.define_singleton_method(:parent_recording) { recording }
    attachment_recording.define_singleton_method(:parent_recording_id) { recording.id }

    ActiveStorage::Blob.stub(:find_signed!, lambda { |id, purpose:|
      raise ActiveSupport::MessageVerifier::InvalidSignature unless id == signed_id && purpose == :attachable_upload

      blob
    }) do
      RecordingStudioAttachable::Attachment.stub(:build_from_blob, attachment) do
        RecordingStudio.stub(:record!, event) do
          uploaded = RecordingStudioAttachable::Services::RecordAttachmentUpload.call(
            parent_recording: recording, signed_blob_id: signed_id, actor: actor, name: "Door"
          )
          replaced = RecordingStudioAttachable::Services::ReplaceAttachmentFile.call(
            attachment_recording: attachment_recording, signed_blob_id: signed_id, actor: actor
          )

          assert uploaded.success?, uploaded.error.to_s
          assert_equal child, uploaded.value
          assert replaced.success?, replaced.error.to_s
        end
      end
    end
  end

  def with_access(&)
    RecordingStudio.configuration.stub(:capability_enabled?, true, &)
  end

  def pin_capability_options!
    singleton = RecordingStudio.singleton_class
    @had_capability_options = singleton.method_defined?(:capability_options)
    @original_capability_options = RecordingStudio.method(:capability_options) if @had_capability_options
    singleton.send(:remove_method, :capability_options) if @had_capability_options
    RecordingStudio.define_singleton_method(:capability_options) { |_name, _for_type: nil, **| {} }
  end

  def restore_capability_options!
    singleton = RecordingStudio.singleton_class
    singleton.send(:remove_method, :capability_options) if singleton.method_defined?(:capability_options)
    return unless @had_capability_options

    original = @original_capability_options
    RecordingStudio.define_singleton_method(:capability_options) { |*args, **kwargs| original.call(*args, **kwargs) }
  end

  def with_pending(count, &)
    ActiveStorage::Blob.stub(:unattached, PendingScope.new(count), &)
  end

  def with_http(body, content_type:, addresses: ["8.8.8.8"], fail_if_called: false, &)
    response = http_response(body, content_type)
    Resolv.stub(:getaddresses, ->(_host) { addresses }) do
      Net::HTTP.stub(:start, lambda { |host, _port, **options, &http_block|
        flunk "HTTP was called for #{host}" if fail_if_called
        assert_equal true, options[:use_ssl]
        http = Object.new
        http.define_singleton_method(:request) do |_request, &request_block|
          request_block ? request_block.call(response) : response
        end
        http_block.call(http)
      }, &)
    end
  end

  def http_response(body, content_type)
    Struct.new(:body, :code, :headers, keyword_init: true) do
      def is_a?(klass)
        return true if klass == Net::HTTPSuccess

        super
      end

      def [](header)
        headers[header]
      end

      def read_body
        yield body.to_s if block_given?
        body
      end
    end.new(body: body, code: "200", headers: { "content-type" => content_type })
  end

  def ticket_blob(recording, actor)
    blob = Object.new
    blob.define_singleton_method(:metadata) { @metadata }
    blob.define_singleton_method(:metadata=) { |value| @metadata = value }
    blob.define_singleton_method(:content_type) { @content_type }
    blob.define_singleton_method(:content_type=) { |value| @content_type = value }
    blob.define_singleton_method(:filename) { @filename }
    blob.define_singleton_method(:filename=) { |value| @filename = value }
    blob.define_singleton_method(:byte_size) { PNG.bytesize }
    blob.define_singleton_method(:open) { |&block| block.call(StringIO.new(PNG)) }
    blob.define_singleton_method(:attachments) { [] }
    blob.define_singleton_method(:signed_id) { |purpose:, expires_in:| "signed-#{purpose}" }
    blob.define_singleton_method(:service_url_for_direct_upload) { |expires_in:| "https://uploads.example.test/put" }
    blob.define_singleton_method(:service_headers_for_direct_upload) { { "Content-Type" => "image/png" } }
    blob.define_singleton_method(:persisted?) { true }
    blob.define_singleton_method(:id) { "blob-1" }
    blob.metadata = RecordingStudioAttachable::DirectUpload.metadata_for(recording: recording, actor: actor)
    blob.content_type = "image/png"
    blob.filename = "door.png"
    blob
  end

  def recording_double(id, **attributes)
    root = RecordingDouble.new(id: "root-1", recordable_type: "Workspace")
    fields = { id: id, recordable_type: "Workspace", root_recording: root }.merge(attributes)
    RecordingDouble.new(**fields)
  end

  def actor_double
    Struct.new(:id).new("actor-1")
  end

  def upload_inline(data:)
    with_access do
      with_pending(0) do
        RecordingStudioAttachable.inline_upload(
          recording: recording_double("parent-1"),
          actor: actor_double,
          data: data,
          filename: "door.png"
        )
      end
    end
  end

  def base64_for_megabytes(megabytes)
    bytes = (megabytes * 1.megabyte).round
    bytes += (3 - (bytes % 3)) % 3
    "A" * (bytes * 4 / 3)
  end

  def context(recording, actor, params)
    Struct.new(:recording, :actor, :params).new(recording, actor, params)
  end

  def install_blob_methods
    ActiveStorage.const_set(:Blob, Class.new) unless defined?(ActiveStorage::Blob)
    blob = ActiveStorage::Blob
    added = []
    {
      unattached: ->(*) { raise NotImplementedError },
      create_and_upload!: ->(**) { raise NotImplementedError },
      find_signed!: ->(*, **) { raise NotImplementedError }
    }.each do |name, body|
      next if blob.respond_to?(name)

      blob.define_singleton_method(name, &body)
      added << name
    end
    added
  end

  def remove_blob_methods(names)
    return if names.blank?

    singleton = ActiveStorage::Blob.singleton_class
    names.each do |name|
      singleton.remove_method(name) if singleton.method_defined?(name) || singleton.private_method_defined?(name)
    end
  end

  def ensure_attachment_class!
    klass =
      if defined?(RecordingStudioAttachable::Attachment)
        RecordingStudioAttachable::Attachment
      else
        RecordingStudioAttachable.const_set(:Attachment, Class.new)
      end
    return if klass.respond_to?(:build_from_blob)

    klass.define_singleton_method(:build_from_blob) { |**| raise NotImplementedError }
  end

  def ensure_api_errors!
    return if defined?(::RecordingStudioApi::InvalidActionInputError)

    api = Module.new
    Object.const_set(:RecordingStudioApi, api)
    error = Class.new(StandardError)
    api.const_set(:Error, error)
    api.const_set(:AuthorizationError, Class.new(error))
    invalid = Class.new(error) do
      attr_reader :details

      def initialize(message = "invalid", details: [])
        super(message)
        @details = details
      end
    end
    api.const_set(:InvalidActionInputError, invalid)
  end
end
