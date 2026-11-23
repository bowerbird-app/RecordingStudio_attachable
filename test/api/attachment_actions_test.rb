# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/record_attachment_upload"
require_relative "../../app/services/recording_studio_attachable/services/record_attachment_uploads"
require_relative "../../app/services/recording_studio_attachable/services/import_attachment"

class AttachmentActionsTest < Minitest::Test
  FakeContext = Struct.new(:recording, :params, :actor, keyword_init: true)
  FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)
  FakeBlob = Struct.new(:id, :persisted, :purged, keyword_init: true) do
    def persisted?
      persisted
    end

    def signed_id(purpose: nil, expires_in: nil)
      "signed-#{purpose}-#{expires_in}"
    end

    def service_url_for_direct_upload(expires_in:)
      "https://uploads.example.test/#{expires_in}"
    end

    def service_headers_for_direct_upload
      { "Content-Type" => "image/png", "Content-MD5" => "checksum" }
    end

    def attachments
      nil
    end

    def purge
      self.purged = true
    end
  end

  def setup
    ensure_blob!
    @configuration = RecordingStudioAttachable.configuration
    @original_hosts = @configuration.import_allowed_hosts.dup
    @original_roles = @configuration.auth_roles.dup
    install_api_errors!
    stub_capability_options!
  end

  def teardown
    @configuration.import_allowed_hosts = @original_hosts
    @configuration.auth_roles = @original_roles
    RecordingStudioAttachable::Api::OpenapiOverrides.clear!
    remove_api_errors!
    restore_capability_options!
  end

  def test_register_waits_until_the_api_gem_is_loaded
    hide_api = RecordingStudioApi
    Object.send(:remove_const, :RecordingStudioApi)

    assert_nil RecordingStudioAttachable::Api.register!
  ensure
    Object.const_set(:RecordingStudioApi, hide_api) unless defined?(::RecordingStudioApi)
  end

  def test_import_role_uses_import_when_that_auth_role_exists
    @configuration.auth_roles = @configuration.auth_roles.merge(import: :admin)

    assert_equal :admin, RecordingStudioAttachable::Api.role_for(:import_attachment)
    assert_equal :edit, RecordingStudioAttachable::Api.role_for(:create_upload)
  end

  def test_create_upload_returns_a_direct_upload_ticket
    blob = FakeBlob.new(id: "blob-1", persisted: true, purged: false)
    created = nil

    ActiveStorage::Blob.stub(:create_before_direct_upload!, lambda { |**attributes|
      created = attributes
      blob
    }) do
      RecordingStudioAttachable::StorageLimit.stub(:with_storage_capacity!, ->(_root, _incoming, &block) { block.call }) do
        ticket = create_upload.call(context(content_type: "image/png", byte_size: 12))

        assert_equal "image/png", created[:content_type]
        assert_equal 12, created[:byte_size]
        assert_equal "1", created.dig(:metadata, RecordingStudioAttachable::DirectUpload::TAG)
        assert_equal "parent-1", created.dig(:metadata, "parent_recording_id")
        assert_equal "Symbol", created.dig(:metadata, "actor_type")
        assert_equal "actor", created.dig(:metadata, "actor_id")
        assert_match(/\Asigned-attachable_upload-/, ticket[:signed_blob_id])
        assert_match(%r{\Ahttps://uploads\.example\.test/}, ticket.dig(:upload, :url))
        assert_equal "image/png", ticket.dig(:upload, :headers, "Content-Type")
        assert ticket[:expires_at].present?
        assert_equal false, blob.purged
      end
    end
  end

  def test_create_upload_rejects_a_disallowed_content_type_before_creating_a_blob
    called = false
    ActiveStorage::Blob.stub(:create_before_direct_upload!, ->(**) { called = true }) do
      error = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        create_upload.call(context(content_type: "application/zip", byte_size: 12))
      end

      assert_includes error.message, "application/zip"
      assert_equal false, called
    end
  end

  def test_create_upload_rejects_an_oversized_file_and_a_negative_size
    ActiveStorage::Blob.stub(:create_before_direct_upload!, ->(**) { flunk "created a blob" }) do
      oversized = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        create_upload.call(context(content_type: "image/png", byte_size: 26.megabytes))
      end
      negative = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        create_upload.call(context(content_type: "image/png", byte_size: -1))
      end

      assert_includes oversized.message, "maximum file size"
      assert_includes negative.message, "zero or more"
    end
  end

  def test_create_upload_uses_its_own_expiry_and_rejects_a_full_pending_queue
    blob = FakeBlob.new(id: "blob-1", persisted: true, purged: false)
    @configuration.direct_upload_expires_in = 2.minutes
    @configuration.pending_upload_limit = 1

    ActiveStorage::Blob.stub(:create_before_direct_upload!, blob) do
      RecordingStudioAttachable::StorageLimit.stub(:with_storage_capacity!, ->(_root, _incoming, &block) { block.call }) do
        ticket = create_upload.call(context(content_type: "image/png", byte_size: 12))
        assert_includes ticket.dig(:upload, :url), 2.minutes.to_s
        assert_in_delta 2.minutes.from_now.to_i, Time.iso8601(ticket[:expires_at]).to_i, 2

        RecordingStudioAttachable::DirectUpload.stub(:pending_count, 1) do
          error = assert_raises(RecordingStudioApi::InvalidActionInputError) do
            create_upload.call(context(content_type: "image/png", byte_size: 12))
          end
          assert_includes error.message, "pending"
        end
      end
    end
  end

  def test_create_upload_drops_the_blob_when_storage_capacity_is_refused
    blob = FakeBlob.new(id: "blob-1", persisted: true, purged: false)

    ActiveStorage::Blob.stub(:create_before_direct_upload!, blob) do
      RecordingStudioAttachable::StorageLimit.stub(:with_storage_capacity!, ->(*) { raise RecordingStudioAttachable::StorageLimitError, "Storage is full" }) do
        error = assert_raises(RecordingStudioApi::InvalidActionInputError) do
          create_upload.call(context(content_type: "image/png", byte_size: 12))
        end

        assert_equal "Storage is full", error.message
        assert_equal true, blob.purged
      end
    end
  end

  def test_attach_uses_one_service_for_a_single_file_and_the_batch_service_for_many
    single = nil
    batch = nil
    success = Struct.new(:success?, :value, :error, :errors).new(true, :recording, nil, [])

    RecordingStudioAttachable::Services::RecordAttachmentUpload.stub(:call, lambda { |**kwargs|
      single = kwargs
      success
    }) do
      RecordingStudioAttachable::Api::AttachmentActions::Payload.stub(:one, { id: "child-1" }) do
        result = attach.call(context_for(signed_blob_id: "signed-1", caption: "Door"))
        assert_equal "child-1", result[:id]
      end
    end

    assert_equal "signed-1", single[:signed_blob_id]
    assert_equal "Door", single[:caption]
    assert_equal :actor, single[:actor]

    many = Struct.new(:success?, :value, :error, :errors).new(true, %i[first second], nil, [])
    RecordingStudioAttachable::Services::RecordAttachmentUploads.stub(:call, lambda { |**kwargs|
      batch = kwargs
      many
    }) do
      RecordingStudioAttachable::Api::AttachmentActions::Payload.stub(:many, { attachments: [{ id: "a" }, { id: "b" }] }) do
        result = attach.call(context_for(attachments: [{ signed_blob_id: "one" }, { signed_blob_id: "two", name: "Two" }]))
        assert_equal 2, result[:attachments].size
      end
    end

    signed_ids = batch[:attachments].map { |item| item[:signed_blob_id] }
    assert_equal %w[one two], signed_ids
    assert_equal "Two", batch[:attachments].last[:name]
  end

  def test_attach_maps_validation_failures_and_authorization_failures
    failure = Struct.new(:success?, :value, :error, :errors).new(false, nil, "Blob exceeds maximum file size", [])
    denied = Struct.new(:success?, :value, :error, :errors).new(false, nil, "Not authorized to upload attachments", [])

    RecordingStudioAttachable::Services::RecordAttachmentUpload.stub(:call, failure) do
      assert_raises(RecordingStudioApi::InvalidActionInputError) do
        attach.call(context_for(signed_blob_id: "signed-1"))
      end
    end

    RecordingStudioAttachable::Services::RecordAttachmentUpload.stub(:call, denied) do
      assert_raises(RecordingStudioApi::AuthorizationError) do
        attach.call(context_for(signed_blob_id: "signed-1"))
      end
    end
  end

  def test_override_openapi_changes_one_type_and_leaves_generic_copy
    RecordingStudioAttachable::Api.override_openapi(
      type: "RecordingStudioPresskits::PressKit",
      action: :import_attachment,
      title: "Press Kit - Import Attachment",
      summary: "Import an image onto this press kit from a web link.",
      description: "Press kit import description."
    )
    RecordingStudioAttachable::Api.override_openapi(
      type: "RecordingStudioPresskits::PressKit",
      action: :attach,
      title: "Press Kit - Attach",
      description: "Press kit attach description."
    )
    RecordingStudioAttachable::Api.override_openapi(
      type: "RecordingStudioPresskits::PressKit",
      action: :create_upload,
      title: "Press Kit - Create Upload",
      summary: "Upload a cover image.",
      description: "Press kit create upload description."
    )

    kit_import = RecordingStudioAttachable::Api.openapi_for(type: "RecordingStudioPresskits::PressKit", action: :import_attachment)
    kit_attach = RecordingStudioAttachable::Api.openapi_for(type: "RecordingStudioPresskits::PressKit", action: :attach)
    kit_upload = RecordingStudioAttachable::Api.openapi_for(type: "RecordingStudioPresskits::PressKit", action: :create_upload)
    workspace_import = RecordingStudioAttachable::Api.openapi_for(type: "Workspace", action: :import_attachment)
    workspace_attach = RecordingStudioAttachable::Api.openapi_for(type: "Workspace", action: :attach)
    workspace_upload = RecordingStudioAttachable::Api.openapi_for(type: "Workspace", action: :create_upload)

    assert_equal "Press Kit - Import Attachment", kit_import[:title]
    assert_equal "Import an image onto this press kit from a web link.", kit_import[:summary]
    assert_equal "Press kit import description.", kit_import[:description]
    assert_equal "Press Kit - Attach", kit_attach[:title]
    assert_equal RecordingStudioAttachable::Api::AttachmentActions::ATTACH_SUMMARY, kit_attach[:summary]
    assert_equal "Press kit attach description.", kit_attach[:description]
    assert_equal "Press Kit - Create Upload", kit_upload[:title]
    assert_equal "Upload a cover image.", kit_upload[:summary]
    assert_equal "Press kit create upload description.", kit_upload[:description]

    assert_equal "Import", workspace_import[:title]
    assert_equal RecordingStudioAttachable::Api::AttachmentActions::IMPORT_ATTACHMENT_SUMMARY, workspace_import[:summary]
    assert_equal RecordingStudioAttachable::Api::AttachmentActions::IMPORT_ATTACHMENT_COPY, workspace_import[:description]
    assert_equal "Attach", workspace_attach[:title]
    assert_equal RecordingStudioAttachable::Api::AttachmentActions::ATTACH_SUMMARY, workspace_attach[:summary]
    assert_equal RecordingStudioAttachable::Api::AttachmentActions::ATTACH_COPY, workspace_attach[:description]
    assert_equal "Upload", workspace_upload[:title]
    assert_equal RecordingStudioAttachable::Api::AttachmentActions::CREATE_UPLOAD_SUMMARY, workspace_upload[:summary]
    assert_equal RecordingStudioAttachable::Api::AttachmentActions::CREATE_UPLOAD_COPY, workspace_upload[:description]

    unknown = assert_raises(ArgumentError) do
      RecordingStudioAttachable::Api.override_openapi(type: "Workspace", action: :grant_access, title: "Nope")
    end
    assert_includes unknown.message, "Unknown Attachable action"
  end

  def test_import_attachment_200_schema_documents_payload_one
    schema = RecordingStudioAttachable::Api::AttachmentActions::IMPORT_ATTACHMENT_OPENAPI.dig(:responses, "200", :content, "application/json", :schema)
    properties = schema.fetch(:properties)

    assert_equal %i[id kind name urls], properties.keys
    assert properties.dig(:urls, :properties).key?(:file)
  end

  def test_create_upload_200_schema_documents_the_ticket
    schema = RecordingStudioAttachable::Api::AttachmentActions::CREATE_UPLOAD_OPENAPI.dig(:responses, "200", :content, "application/json", :schema)
    properties = schema.fetch(:properties)

    assert properties.key?(:signed_blob_id)
    assert properties.dig(:upload, :properties).key?(:url)
    assert properties.dig(:upload, :properties).key?(:headers)
    assert properties.key?(:expires_at)
  end

  def test_create_upload_contract_has_approved_field_wording
    contract = RecordingStudioAttachable::Api::AttachmentContracts.create_upload
    fields = contract.fetch(:fields)

    assert_equal "The file name to store, such as cover.jpg. Required. Send the name you want on the blob.", fields.dig(:filename, :description)
    assert_equal "The file size in bytes. Required. Use zero or more. It must match this record type's allowed content types and size and count limits, as shown in the action description.", fields.dig(:byte_size, :description)
    assert_equal "MD5 checksum of the file bytes, Base64-encoded, as Active Storage expects. Required. Compute it from the bytes before you call create_upload.", fields.dig(:checksum, :description)
    assert_equal "The file's content type. Required. It must match this record type's allowed content types and size and count limits, as shown in the action description. image/* does not include image/svg+xml unless that exact type is named in the allow list.", fields.dig(:content_type, :description)
  end

  def test_tool_description_is_printed_once_and_covers_inputs_and_returns
    actions = {
      create_upload: RecordingStudioAttachable::Api::AttachmentContracts.create_upload,
      attach: RecordingStudioAttachable::Api::AttachmentContracts.attach,
      import_attachment: RecordingStudioAttachable::Api::AttachmentContracts.import_attachment
    }

    actions.each do |name, contract|
      openapi = RecordingStudioAttachable::Api.openapi_for(type: "Workspace", action: name)
      summary = openapi.fetch(:summary)
      description = openapi.fetch(:description)
      shown = [summary, description].join("\n\n")

      refute_equal summary, description, "#{name} summary repeats the description"
      assert_equal 1, shown.scan(description).size, "#{name} description is printed more than once"
      assert_match(/returns/i, description, "#{name} does not say what it returns")
      refute_match(/add file|press kit/i, description, "#{name} names another product's tool")

      contract.fetch(:fields).each do |field, rules|
        text = rules.to_h[:description].to_s
        assert text.present?, "#{name} #{field} has no description"
        refute_match(/press kit/i, text, "#{name} #{field} names a press kit")
      end
    end

    upload = actions.fetch(:create_upload).fetch(:fields)
    attach = actions.fetch(:attach).fetch(:fields)
    import = actions.fetch(:import_attachment).fetch(:fields)
    upload_description = RecordingStudioAttachable::Api.openapi_for(type: "Workspace", action: :create_upload).fetch(:description)
    attach_description = RecordingStudioAttachable::Api.openapi_for(type: "Workspace", action: :attach).fetch(:description)
    import_description = RecordingStudioAttachable::Api.openapi_for(type: "Workspace", action: :import_attachment).fetch(:description)

    assert_includes upload_description, "signed_blob_id"
    assert_includes upload_description, "upload.url"
    assert_includes upload_description, "upload.headers"
    assert_includes upload_description, "expires_at"
    assert_includes attach_description, "id"
    assert_includes attach_description, "kind"
    assert_includes attach_description, "urls.file"
    assert_includes import_description, "urls.file"
    assert_includes attach.fetch(:signed_blob_id).fetch(:description), "create_upload"
    assert_includes attach.fetch(:attachments).fetch(:description), "signed_blob_id"
    assert_includes import.fetch(:url).fetch(:description), "HTTPS"
    assert_includes import.fetch(:url).fetch(:description), "host app"
    refute_includes import.fetch(:url).fetch(:description), "config."
    refute_includes upload_description, "config."
    refute_includes attach_description, "config."
    refute_includes import_description, "config."
    assert_includes import_description, "host app must allow"
    assert_match(%r{image/svg\+xml}, upload.fetch(:content_type).fetch(:description))
    refute_includes upload.fetch(:byte_size).fetch(:description), "25 MB"
    refute_includes attach.fetch(:attachments).fetch(:description), "20 files"
  end

  def test_openapi_for_states_the_type_rules_and_keeps_the_global_default
    kit = "KitCover"
    with_type_rules(kit, kit_cover_rules) do
      upload = RecordingStudioAttachable::Api.openapi_for(type: kit, action: :create_upload)
      attach = RecordingStudioAttachable::Api.openapi_for(type: kit, action: :attach)
      default_upload = RecordingStudioAttachable::Api.openapi_for(type: "Workspace", action: :create_upload)
      content_type = field_description(upload, :content_type)
      byte_size = field_description(upload, :byte_size)
      limits = RecordingStudioAttachable::Api::UploadRules.limits_paragraph(kit)

      assert_includes content_type, "image/svg+xml"
      assert_includes content_type, "allowed because it is named"
      assert_includes byte_size, "10 MB"
      assert_includes limits, "10 MB"
      assert_includes limits, "Allowed kinds are image."
      assert_includes upload.fetch(:description), limits
      assert_includes attach.fetch(:description), limits
      [content_type, byte_size, limits, upload.fetch(:description)].each do |text|
        refute_match(/pdf/i, text)
      end

      assert_equal RecordingStudioAttachable::Api::AttachmentActions::CREATE_UPLOAD_COPY, default_upload.fetch(:description)
      assert_nil default_upload[:request_body]
      default_type = RecordingStudioAttachable::Api::AttachmentContracts.create_upload.dig(:fields, :content_type, :description)
      refute_includes default_type, "application/pdf"
      assert_includes default_type, "image/svg+xml"
      assert_includes default_type, "does not include"
    end
  end

  def test_static_upload_fields_omit_default_mime_and_size
    note = "this record type's allowed content types and size and count limits, as shown in the action description"
    fields = {
      content_type: RecordingStudioAttachable::Api::AttachmentContracts.create_upload.dig(:fields, :content_type, :description),
      byte_size: RecordingStudioAttachable::Api::AttachmentContracts.create_upload.dig(:fields, :byte_size, :description),
      attachments: RecordingStudioAttachable::Api::AttachmentContracts.attach.dig(:fields, :attachments, :description)
    }

    assert_equal "List of files to attach in one call. Each item has signed_blob_id from its own create_upload call, plus optional name, description, caption, credit, and alt_text. Send this or signed_blob_id, not both. It must match this record type's allowed content types and size and count limits, as shown in the action description.", fields.fetch(:attachments)

    fields.each do |name, text|
      refute_includes text, "application/pdf", "#{name} names application/pdf"
      refute_includes text, "25 MB", "#{name} names the default size"
      refute_includes text, "20 files", "#{name} names the default count"
      refute_match(/default (allow|cap|size)/i, text, "#{name} states a default")
      assert_includes text, note, "#{name} does not point at the action description"
    end
  end

  def test_per_record_upload_text_follows_an_images_only_record
    type = "PressKit"
    with_type_rules(type, images_only_rules) do
      upload = RecordingStudioAttachable::Api.openapi_for(type: type, action: :create_upload)
      attach = RecordingStudioAttachable::Api.openapi_for(type: type, action: :attach)
      content_type = field_description(upload, :content_type)
      byte_size = field_description(upload, :byte_size)
      attachments = field_description(attach, :attachments)
      texts = [content_type, byte_size, attachments, upload.fetch(:description), attach.fetch(:description)]

      assert_equal "The file type, such as image/png. Required. This record allows image/*. image/* does not include image/svg+xml.", content_type
      assert_equal "The file size in bytes. Required. Use zero or more. The size cap is 8 MB.", byte_size
      assert_equal "List of files to attach in one call. Each item has signed_blob_id from its own create_upload call, plus optional name, description, caption, credit, and alt_text. Send this or signed_blob_id, not both. A batch can include up to 3 files.", attachments
      texts.each { |text| refute_includes text, "application/pdf" }
    end
  end

  def test_kit_cover_refuses_pdf_and_allows_svg_only_when_it_is_named
    kit = "KitCover"
    images_only = "ImagesOnly"

    with_type_rules(kit, kit_cover_rules) do
      created = nil
      blob = FakeBlob.new(id: "blob-svg", persisted: true, purged: false)
      ActiveStorage::Blob.stub(:create_before_direct_upload!, lambda { |**attributes|
        created = attributes
        blob
      }) do
        RecordingStudioAttachable::StorageLimit.stub(:with_storage_capacity!, ->(_root, _incoming, &block) { block.call }) do
          RecordingStudioAttachable::DirectUpload.stub(:pending_count, 0) do
            pdf = assert_raises(RecordingStudioApi::InvalidActionInputError) do
              create_upload.call(context_for_type(kit, content_type: "application/pdf", byte_size: 12))
            end
            assert_includes pdf.message, "application/pdf"
            assert_includes pdf.message, "not allowed"

            ticket = create_upload.call(context_for_type(kit, content_type: "image/svg+xml", byte_size: 12))
            assert_equal "image/svg+xml", created[:content_type]
            assert_match(/\Asigned-attachable_upload-/, ticket[:signed_blob_id])

            oversized = assert_raises(RecordingStudioApi::InvalidActionInputError) do
              create_upload.call(context_for_type(kit, content_type: "image/svg+xml", byte_size: 10.megabytes + 1))
            end
            assert_includes oversized.message, "maximum file size"
          end
        end
      end
    end

    with_type_rules(images_only, kit_cover_rules.merge(allowed_content_types: ["image/*"])) do
      called = false
      ActiveStorage::Blob.stub(:create_before_direct_upload!, ->(**) { called = true }) do
        svg = assert_raises(RecordingStudioApi::InvalidActionInputError) do
          create_upload.call(context_for_type(images_only, content_type: "image/svg+xml", byte_size: 12))
        end
        assert_includes svg.message, "image/svg+xml"
        assert_includes svg.message, "not allowed"
        assert_equal false, called
      end
    end
  end

  def test_import_rejects_a_private_address_and_a_host_outside_the_allowlist
    @configuration.import_allowed_hosts = ["files.example.test"]

    disallowed = assert_raises(RecordingStudioApi::InvalidActionInputError) do
      import.call(context_for(url: "https://evil.example.test/secret.png"))
    end
    assert_includes disallowed.message, "not allowed"

    Resolv.stub(:getaddresses, ->(_host) { ["127.0.0.1"] }) do
      private_host = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        import.call(context_for(url: "https://files.example.test/secret.png"))
      end
      assert_includes private_host.message, "private address"
    end
  end

  private

  def create_upload
    RecordingStudioAttachable::Api::AttachmentActions::CreateUpload
  end

  def attach
    RecordingStudioAttachable::Api::AttachmentActions::Attach
  end

  def import
    RecordingStudioAttachable::Api::AttachmentActions::ImportAttachment
  end

  def context(content_type:, byte_size:)
    root = FakeRecording.new(id: "root-1", recordable_type: "Workspace")
    recording = FakeRecording.new(id: "parent-1", recordable_type: "Workspace", root_recording: root)
    FakeContext.new(
      recording: recording,
      actor: :actor,
      params: { filename: "photo.png", byte_size: byte_size, checksum: "checksum", content_type: content_type }
    )
  end

  def kit_cover_rules
    {
      allowed_content_types: ["image/*", "image/svg+xml"],
      max_file_size: 10.megabytes,
      enabled_attachment_kinds: [:image]
    }
  end

  def images_only_rules
    {
      allowed_content_types: ["image/*"],
      max_file_size: 8.megabytes,
      max_file_count: 3,
      enabled_attachment_kinds: [:image]
    }
  end

  def with_type_rules(type, rules)
    studio = RecordingStudio
    singleton = studio.singleton_class
    singleton.send(:remove_method, :capability_options) if singleton.method_defined?(:capability_options)
    studio.define_singleton_method(:capability_options) do |name, for_type: nil, **|
      next rules if name.to_sym == :attachable && for_type.to_s == type

      {}
    end
    yield
  ensure
    singleton = RecordingStudio.singleton_class
    singleton.send(:remove_method, :capability_options) if singleton.method_defined?(:capability_options)
    RecordingStudio.define_singleton_method(:capability_options) { |_name, _for_type: nil, **| {} }
  end

  def field_description(openapi, name)
    openapi.dig(:request_body, :content, "application/json", :schema, :properties, name, :description)
  end

  def context_for_type(type, content_type:, byte_size:)
    root = FakeRecording.new(id: "root-1", recordable_type: type)
    recording = FakeRecording.new(id: "parent-1", recordable_type: type, root_recording: root)
    FakeContext.new(
      recording: recording,
      actor: :actor,
      params: { filename: "cover.svg", byte_size: byte_size, checksum: "checksum", content_type: content_type }
    )
  end

  def context_for(params)
    root = FakeRecording.new(id: "root-1", recordable_type: "Workspace")
    recording = FakeRecording.new(id: "parent-1", recordable_type: "Workspace", root_recording: root)
    FakeContext.new(recording: recording, actor: :actor, params: params)
  end

  def ensure_blob!
    ActiveStorage.const_set(:Blob, Class.new) unless defined?(ActiveStorage::Blob)
    return if ActiveStorage::Blob.respond_to?(:create_before_direct_upload!)

    ActiveStorage::Blob.define_singleton_method(:create_before_direct_upload!) { |**| raise NotImplementedError }
  end

  def install_api_errors!
    return if defined?(::RecordingStudioApi)

    stub = Module.new
    Object.const_set(:RecordingStudioApi, stub)
    error = Class.new(StandardError)
    stub.const_set(:Error, error)
    invalid = Class.new(error) do
      attr_reader :details

      def initialize(message = "invalid", details: [])
        super(message)
        @details = details
      end
    end
    stub.const_set(:InvalidActionInputError, invalid)
    stub.const_set(:AuthorizationError, Class.new(error))
    @installed_api_errors = true
  end

  def remove_api_errors!
    return unless @installed_api_errors

    Object.send(:remove_const, :RecordingStudioApi)
  end

  def stub_capability_options!
    @studio = RecordingStudio
    singleton = @studio.singleton_class
    @had_capability_options = singleton.method_defined?(:capability_options)
    @original_capability_options = @studio.method(:capability_options) if @had_capability_options
    singleton.send(:remove_method, :capability_options) if @had_capability_options
    @studio.define_singleton_method(:capability_options) { |_name, _for_type: nil, **| {} }
  end

  def restore_capability_options!
    singleton = @studio.singleton_class
    singleton.send(:remove_method, :capability_options) if singleton.method_defined?(:capability_options)
    return unless @had_capability_options

    original = @original_capability_options
    @studio.define_singleton_method(:capability_options) { |*args, **kwargs| original.call(*args, **kwargs) }
  end
end
