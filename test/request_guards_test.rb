# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"

class RequestGuardsTest < ActionController::TestCase
  class ProbeController < RecordingStudioAttachable::ApplicationController
    def show
      render_upload_provider_modal_event(
        type: "provider-auth-complete",
        redirect_path: "/uploads",
        close_window: true
      )
    end
  end

  tests ProbeController

  def setup
    @controller = ProbeController.new
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw { get "/probe", to: "request_guards_test/probe#show" }
    @previous_configuration = RecordingStudioAttachable.configuration
    @configuration = RecordingStudioAttachable::Configuration.new
    RecordingStudioAttachable.instance_variable_set(:@configuration, @configuration)
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @previous_configuration)
  end

  def test_the_provider_modal_event_page_posts_the_payload_and_closes
    get :show

    assert_response :ok
    assert_includes response.media_type, "html"
    assert_includes response.body, "provider-auth-complete"
    assert_includes response.body, "/uploads"
    assert_includes response.body, "window.close()"
    assert_includes response.body, "Returning to the upload page"
  end

  def test_provider_request_params_keep_the_modal_identity_and_a_safe_return
    @controller.params = ActionController::Parameters.new(
      embed: "modal",
      provider_key: "my_cloud",
      provider_modal_id: "modal-1",
      redirect_mode: "return_to",
      return_to: "/pages/1"
    )

    assert_equal(
      { embed: "modal", provider_key: "my_cloud", provider_modal_id: "modal-1" },
      @controller.send(:upload_provider_request_params)
    )
    flow = @controller.send(:upload_flow_params)
    assert_equal "modal", flow[:embed]
    assert_equal "my_cloud", flow[:provider_key]
    assert_equal "/pages/1", flow[:return_to]

    @controller.params = ActionController::Parameters.new(embed: "page")
    assert_nil @controller.send(:upload_provider_request_params)[:embed]
  end

  def test_a_broken_request_origin_rejects_an_off_site_return
    @request = ActionDispatch::TestRequest.create
    @controller.set_request!(@request)
    @request.define_singleton_method(:base_url) { "http://[" }

    assert_nil @controller.send(:validated_local_redirect_target, "https://evil.example/phish")
  end

  def test_only_visible_upload_providers_are_offered
    shown = RecordingStudioAttachable::UploadProvider.new(key: :shown, label: "Shown", url: "/shown")
    hidden = RecordingStudioAttachable::UploadProvider.new(key: :hidden, label: "Hidden", url: "/hidden", visible: false)
    @configuration.upload_providers = [shown, hidden]
    recording = Struct.new(:id).new("rec-1")

    get :show
    offered = @controller.send(:configured_upload_providers, recording)

    assert_equal [:shown], offered.map(&:key)
  end

  def test_authorized_paths_use_the_attachment_delivery_url
    attachment = Object.new
    attachment.define_singleton_method(:preview_target_named) { |_name| :ready }
    attachment.define_singleton_method(:original_url) { |rails_url:| "https://images.example.test#{rails_url}" }
    attachment.define_singleton_method(:url_for_variant) { |_name, rails_url:| "https://images.example.test#{rails_url}" }
    recording = Object.new
    recording.define_singleton_method(:id) { "att-1" }
    recording.define_singleton_method(:recordable) { attachment }
    @controller.define_singleton_method(:attachment_file_path) { |record| "/attachments/#{record.id}/file" }
    @controller.define_singleton_method(:attachment_preview_file_path) do |record, variant_name:|
      "/attachments/#{record.id}/preview/#{variant_name}"
    end

    assert_equal(
      "https://images.example.test/attachments/att-1/file",
      @controller.send(:authorized_attachment_file_path, recording)
    )
    assert_equal(
      "https://images.example.test/attachments/att-1/preview/large",
      @controller.send(:authorized_attachment_preview_path, recording, :large)
    )
  end

  def test_provider_csrf_token_is_present_for_the_request
    get :show

    token = @controller.send(:provider_csrf_token)

    assert_kind_of String, token
    assert token.present?
  end
end
