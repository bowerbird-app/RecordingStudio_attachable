# frozen_string_literal: true

require "test_helper"
require "base64"
require "stringio"

class OwnerAvailabilityTest < ActionDispatch::IntegrationTest
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
  HOOK = :attachable_available_for?

  class Boom < StandardError; end

  setup do
    password = "Password123!"
    @user = User.create!(
      email: "owner-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      name: "Owner"
    )
    sign_in @user
    Current.actor = @user
    workspace = Workspace.create!(name: "Availability #{SecureRandom.hex(4)}")
    @root = RecordingStudio.create_root_recording!(workspace, actor: @user)
    grant_access!(@user)
    @attachment_name = "Availability photo"
    @attachment = attach_image("availability.png", @attachment_name)
    process_preview(@attachment)
  end

  teardown do
    Current.actor = nil if defined?(Current)
    remove_hook
  end

  test "read routes allow an owner whose hook returns true" do
    calls = []
    with_hook(lambda { |actor:, action:, recording:|
      calls << [actor, action, recording]
      true
    }) do
      each_read(@attachment) do |name|
        assert_response :success, name.to_s
        assert_read_body(name)
      end
    end

    view_calls = calls.select { |actor, action, recording| action == :view && actor == @user && recording == @root }
    assert_operator view_calls.length, :>=, 1
  end

  test "read routes stay available when the owner has no hook" do
    each_read(@attachment) do |name|
      assert_response :success, name.to_s
      assert_read_body(name)
    end
  end

  test "read routes are not found when the hook returns false nil or another object" do
    [false, nil, :available].each do |result|
      with_hook(->(**) { result }) do
        each_read(@attachment) do |name|
          assert_not_found(name, result.inspect)
        end
      end
    end
  end

  test "read routes are not found when the hook is private" do
    install_visibility(:private)
    logs = capture_logs do
      each_read(@attachment) { |name| assert_not_found(name, "private") }
    end

    assert_not_includes logs, "NoMethodError"
    assert_not_includes logs, "secret"
  end

  test "read routes are not found when the hook raises and the log names the class only" do
    with_hook(->(**) { raise Boom, "secret draft reason" }) do
      logs = capture_logs do
        each_read(@attachment) { |name| assert_not_found(name, "raise") }
      end

      assert_includes logs, "Boom"
      assert_not_includes logs, "secret draft reason"
    end
  end

  test "json reads are not found and a role refusal stays forbidden" do
    with_hook(->(**) { false }) do
      get recording_studio_attachable.attachment_path(@attachment), as: :json
      assert_response :not_found
      assert_equal "Not found", JSON.parse(response.body).fetch("error")
    end

    calls = []
    outsider = User.create!(
      email: "outsider-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      name: "Outsider"
    )
    with_hook(lambda { |actor:, action:, recording:|
      calls << [actor, action, recording]
      true
    }) do
      sign_in outsider
      get recording_studio_attachable.attachment_file_path(@attachment)
      assert_response :redirect
      assert_includes flash[:alert].to_s, "Not authorized"
      get recording_studio_attachable.attachment_file_path(@attachment), as: :json
      assert_response :forbidden
      assert_includes response.body, "Not authorized"
    end
    assert_empty calls
  end

  test "remove attachment follows the hook" do
    assert_remove(->(**) { true }, success: true)
    assert_remove(->(**) { false }, success: false)
    assert_remove(->(**) { nil }, success: false)
    assert_remove(->(**) { :available }, success: false)
    install_visibility(:private)
    assert_service_refusal
    remove_hook
    with_hook(->(**) { raise Boom, "secret draft reason" }) do
      logs = capture_logs { assert_service_refusal }
      assert_includes logs, "Boom"
      assert_not_includes logs, "secret draft reason"
    end
    remove_hook
    assert_remove(nil, success: true)
  end

  test "a write route keeps the current response when the hook refuses" do
    spare = attach_image("spare.png", "Spare")
    with_hook(->(**) { false }) do
      delete recording_studio_attachable.destroy_attachment_path(spare)
      assert_response :redirect
      assert_includes flash[:alert].to_s, "Not authorized"
      assert RecordingStudio::Recording.exists?(spare.id)

      delete recording_studio_attachable.destroy_attachment_path(spare), as: :json
      assert_response :forbidden
      assert_includes response.body, "Not authorized"
      assert RecordingStudio::Recording.exists?(spare.id)
    end
  end

  private

  def each_read(recording)
    {
      show: -> { get recording_studio_attachable.attachment_path(recording) },
      file: -> { get recording_studio_attachable.attachment_file_path(recording) },
      download: -> { get recording_studio_attachable.download_attachment_path(recording) },
      preview: -> { get recording_studio_attachable.attachment_preview_file_path(recording, variant_name: "large") },
      listing: -> { get recording_studio_attachable.recording_attachments_path(@root) },
      picker: -> { get recording_studio_attachable.recording_attachment_picker_path(@root), as: :json }
    }.each do |name, request|
      request.call
      yield name
    end
  end

  def assert_read_body(name)
    case name
    when :file, :download
      assert_equal PNG, response.body
    when :preview
      assert_operator response.body.bytesize, :>, 0
    when :show, :listing, :picker
      assert_includes response.body, @attachment_name
    end
  end

  def assert_not_found(name, label)
    assert_response :not_found, "#{name} #{label}"
    assert_not_equal PNG, response.body
    assert_not_includes response.body, @attachment_name
    assert_not_includes response.body, "Not authorized"
    assert_not_includes response.body, "secret draft reason"
  end

  def assert_remove(hook, success:)
    attachment = attach_image("remove-#{SecureRandom.hex(2)}.png", "Remove")
    with_hook(hook) do
      result = RecordingStudioAttachable::Services::RemoveAttachment.call(
        attachment_recording: attachment,
        actor: @user
      )
      assert_equal success, result.success?, result.error.to_s
      if success
        assert_not_includes result.error.to_s, "secret"
      else
        assert_includes result.error, "Not authorized"
        assert RecordingStudio::Recording.exists?(attachment.id)
      end
    end
  end

  def assert_service_refusal
    attachment = attach_image("refused-#{SecureRandom.hex(2)}.png", "Refused")
    result = RecordingStudioAttachable::Services::RemoveAttachment.call(
      attachment_recording: attachment,
      actor: @user
    )
    assert result.failure?, result.error.to_s
    assert_includes result.error, "Not authorized"
    assert_not_includes result.error, "secret draft reason"
    assert RecordingStudio::Recording.exists?(attachment.id)
  end

  def with_hook(hook)
    install_hook(hook)
    yield
  ensure
    remove_hook
  end

  def install_hook(hook)
    return if hook.nil?

    Workspace.define_method(HOOK, hook)
  end

  def install_visibility(visibility)
    Workspace.define_method(HOOK) { |**| true }
    Workspace.send(visibility, HOOK)
  end

  def remove_hook
    return unless Workspace.method_defined?(HOOK) || Workspace.private_method_defined?(HOOK)

    Workspace.remove_method(HOOK)
  end

  def capture_logs
    io = StringIO.new
    previous = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = previous
  end

  def attach_image(filename, name)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(PNG),
      filename: filename,
      content_type: "image/png"
    )
    attachment = RecordingStudioAttachable::Attachment.build_from_blob(
      blob: blob,
      name: name,
      root_recording: @root
    )
    RecordingStudio.record!(
      action: "attachment_uploaded",
      recordable: attachment,
      root_recording: @root,
      parent_recording: @root,
      actor: @user
    ).recording
  end

  def process_preview(recording)
    target = recording.recordable.preview_target_named(:large)
    raise "preview target missing" if target.blank?

    target.processed
  end

  def grant_access!(actor)
    authorizer = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: @root, actor: actor)
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = authorizer
  end
end
