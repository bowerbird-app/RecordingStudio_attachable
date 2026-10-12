# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../lib/recording_studio_attachable/dropbox/app/controllers/recording_studio_attachable/dropbox/application_controller"

class DropboxApplicationControllerTest < Minitest::Test
  class ProbeController < RecordingStudioAttachable::Dropbox::ApplicationController
  end

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    @controller = ProbeController.new
    @request = ActionDispatch::TestRequest.create
    @response = ActionDispatch::TestResponse.create
    @session = {}
    @controller.set_request!(@request)
    @controller.set_response!(@response)
    @controller.define_singleton_method(:session) { @test_session }
    @controller.instance_variable_set(:@test_session, @session)
    @controller.define_singleton_method(:params) { { popup: "1" } }
    @controller.define_singleton_method(:current_upload_provider_key) { "dropbox" }
    @controller.define_singleton_method(:current_upload_provider_modal_id) { nil }
    @controller.define_singleton_method(:embedded_upload_provider_request?) { false }
    @controller.define_singleton_method(:attachment_redirect_params) { {} }
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_ensure_dropbox_enabled_requires_the_addon_to_be_enabled
    error = assert_raises(RecordingStudioAttachable::DependencyUnavailableError) do
      @controller.send(:ensure_dropbox_enabled!)
    end

    assert_equal "Dropbox addon is not enabled", error.message
  end

  def test_store_and_consume_dropbox_state_round_trips_pkce_verifier
    state, verifier = @controller.send(:store_dropbox_state!, recording_id: "rec-1", provider_key: "dropbox")
    payload = @controller.send(:consume_dropbox_state!, state)

    assert_equal "rec-1", payload.fetch("recording_id")
    assert_equal "dropbox", payload.fetch("provider_key")
    assert_equal verifier, payload.fetch("code_verifier")
    assert_nil @session.dig("recording_studio_attachable_dropbox", "oauth_state")
  end

  def test_consume_dropbox_state_rejects_mismatched_values
    @session["recording_studio_attachable_dropbox"] = {
      "oauth_state" => { "value" => "expected" }
    }

    error = assert_raises(RecordingStudioAttachable::Error) do
      @controller.send(:consume_dropbox_state!, "actual")
    end

    assert_equal "Dropbox authorization state did not match", error.message
  end
end
