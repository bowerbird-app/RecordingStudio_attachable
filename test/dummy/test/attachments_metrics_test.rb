# frozen_string_literal: true

require "test_helper"

class AttachmentsMetricsTest < ActiveSupport::TestCase
  setup do
    @actor = create_user("metrics-staff-#{SecureRandom.hex(4)}@example.com")
    @denied = create_user("metrics-denied-#{SecureRandom.hex(4)}@example.com")
    workspace = Workspace.create!(name: "Metrics #{SecureRandom.hex(4)}")
    Current.actor = @actor
    @root = RecordingStudio.root_recording_for(workspace)
    grant_view!(@actor, @root, role: :admin)
    install_admin_resolver!(@root)
    RecordingStudioMetrics.registry.reset!
    RecordingStudioAttachable::Metrics.register!
  end

  teardown do
    RecordingStudioAdmin.configuration.access_recording_resolver = nil
  end

  test "registers the attachments metrics on the operations API" do
    identifiers = RecordingStudioMetrics.for_resource(:attachments).map(&:identifier)

    assert_includes identifiers, "attachments.storage_used"
    assert_includes identifiers, "attachments.uploads_over_time"
    assert_includes identifiers, "attachments.by_kind"
    assert_includes identifiers, "attachments.by_content_type"

    assert_equal "Storage used", RecordingStudioMetrics.find("attachments.storage_used").title
    assert_equal "Uploads over time", RecordingStudioMetrics.find("attachments.uploads_over_time").title
    assert_equal "Uploads by kind", RecordingStudioMetrics.find("attachments.by_kind").title
    assert_equal "Uploads by content type", RecordingStudioMetrics.find("attachments.by_content_type").title

    RecordingStudioMetrics.for_resource(:attachments).each do |definition|
      assert_equal [:operations], definition.exposed_apis
      assert_equal :site, definition.blast_radius
    end
  end

  test "storage_used sums live current snapshots and ignores trash and revisions" do
    jpeg = import_file(@root, "hero.jpg", "image/jpeg", "jpeg-bytes")
    import_file(@root, "notes.txt", "text/plain", "plain-text-bytes")
    trashed = import_file(@root, "gone.jpg", "image/jpeg", "trashed-bytes")
    jpeg.revise_attachment_metadata(actor: @actor, caption: "Revised caption")
    trashed.remove_attachment(actor: @actor)

    live_ids = RecordingStudio::Recording.where(
      recordable_type: "RecordingStudioAttachable::Attachment",
      trashed_at: nil
    ).select(:recordable_id)
    expected = RecordingStudioAttachable::Attachment.where(id: live_ids).sum(:byte_size)
    raw_total = RecordingStudioAttachable::Attachment.sum(:byte_size)

    result = execute("attachments.storage_used")

    assert_equal expected, result.value
    assert_operator raw_total, :>, result.value
    assert_operator RecordingStudioAttachable::Attachment.where(id: jpeg.reload.recordable_id).count, :==, 1
    assert_operator RecordingStudioAttachable::Attachment.where(name: jpeg.recordable.name).count, :>=, 2
  end

  test "uploads_over_time counts created_at in the window" do
    travel_to Time.utc(2026, 3, 10, 12) do
      import_file(@root, "march.txt", "text/plain", "march-bytes")
    end
    travel_to Time.utc(2026, 4, 2, 12) do
      import_file(@root, "april.txt", "text/plain", "april-bytes")
    end

    result = execute(
      "attachments.uploads_over_time",
      interval: :month,
      start_at: Time.utc(2026, 3, 1),
      end_at: Time.utc(2026, 5, 1)
    )

    values = result.data.to_h { |row| [row[:date], row[:value]] }
    assert_operator values["2026-03-01"], :>=, 1
    assert_operator values["2026-04-01"], :>=, 1
    assert_equal "records_created_during_period", result.metadata[:semantics]
  end

  test "by_kind and by_content_type use the current live snapshot" do
    import_file(@root, "kind.jpg", "image/jpeg", "image-bytes")
    import_file(@root, "kind.txt", "text/plain", "text-bytes")
    trashed = import_file(@root, "kind-gone.pdf", "application/pdf", "pdf-bytes")
    trashed.remove_attachment(actor: @actor)

    kinds = execute("attachments.by_kind").data.to_h { |row| [row[:key].to_s, row[:value]] }
    types = execute("attachments.by_content_type").data.to_h { |row| [row[:key].to_s, row[:value]] }

    live_ids = RecordingStudio::Recording.where(
      recordable_type: "RecordingStudioAttachable::Attachment",
      trashed_at: nil
    ).select(:recordable_id)
    live = RecordingStudioAttachable::Attachment.where(id: live_ids)

    assert_equal live.where(attachment_kind: "image").count, kinds["image"]
    assert_equal live.where(attachment_kind: "file").count, kinds["file"]
    assert_equal live.where(content_type: "image/jpeg").count, types["image/jpeg"]
    assert_equal live.where(content_type: "text/plain").count, types["text/plain"]
    assert_nil types["application/pdf"]
  end

  test "execute handler returns the value when access allows" do
    payload = RecordingStudioMetrics::Api::ExecuteHandler.call(
      build_api_context(@actor, name: "storage_used")
    )

    assert_equal "attachments.storage_used", payload[:metric]
    assert_equal execute("attachments.storage_used").value, payload[:value]
  end

  test "execute handler is 403 when access denies" do
    error = assert_raises(RecordingStudioMetrics::Errors::AuthorizationError) do
      RecordingStudioMetrics::Api::ExecuteHandler.call(
        build_api_context(@denied, name: "storage_used")
      )
    end

    assert_match(/not authorized/i, error.message)
  end

  test "staff can_view and a non-admin cannot" do
    assert RecordingStudioAttachable::Api::Access.can_view?(build_api_context(@actor))
    refute RecordingStudioAttachable::Api::Access.can_view?(build_api_context(@denied))
  end

  test "discovery hides metrics from denied callers" do
    denied = RecordingStudioMetrics::Api::DiscoveryHandler.call(build_api_context(@denied))
    denied_ids = denied.fetch(:metrics).map { |row| row[:identifier] }
    refute_includes denied_ids, "attachments.storage_used"

    allowed = RecordingStudioMetrics::Api::DiscoveryHandler.call(build_api_context(@actor))
    allowed_ids = allowed.fetch(:metrics).map { |row| row[:identifier] }

    assert_includes allowed_ids, "attachments.storage_used"
  end

  private

  def execute(identifier, **params)
    RecordingStudioMetrics.execute(
      identifier,
      context: site_context,
      **params
    )
  end

  def site_context
    RecordingStudioMetrics::Context.new(
      actor: @actor,
      scope: :site,
      site_authorized: true,
      timezone: "UTC"
    )
  end

  def build_api_context(actor, name: "storage_used")
    grant = Struct.new(:actor).new(actor)
    params = {
      resource: "attachments",
      name: name,
      interval: nil,
      start: nil,
      start_at: nil,
      end: nil,
      end_at: nil,
      timezone: "UTC",
      filters: {}
    }
    context = Object.new
    context.define_singleton_method(:access_grant) { grant }
    context.define_singleton_method(:api_client) { actor }
    context.define_singleton_method(:access_recording) { nil }
    context.define_singleton_method(:root_recording) { nil }
    context.define_singleton_method(:api_key) { :operations }
    context.define_singleton_method(:params) { params }
    context
  end

  def install_admin_resolver!(recording)
    unless defined?(RecordingStudioAdmin)
      admin = Module.new
      configuration = Struct.new(:access_recording_resolver).new
      admin.define_singleton_method(:configuration) { configuration }
      Object.const_set(:RecordingStudioAdmin, admin)
    end

    RecordingStudioAdmin.configuration.access_recording_resolver = ->(_context) { recording }
  end

  def grant_view!(actor, recording, role: :view)
    original = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role,
      manager_actor: actor
    )
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end

  def create_user(email)
    User.create!(
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!",
      name: email.split("@").first
    )
  end

  def import_file(root, filename, content_type, body)
    root.import_attachment(
      io: StringIO.new(body),
      filename: filename,
      content_type: content_type,
      name: filename,
      actor: @actor,
      identify: false,
      source: "metrics_test"
    )
  end
end
