# frozen_string_literal: true

require "test_helper"
require_relative "dropbox_fakes"
require_relative "dummy/app/models/current"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../lib/recording_studio_attachable/dropbox/app/controllers/recording_studio_attachable/dropbox/application_controller"
require_relative "../lib/recording_studio_attachable/dropbox/app/controllers/recording_studio_attachable/dropbox/imports_controller"
require_relative "../lib/recording_studio_attachable/dropbox/app/controllers/recording_studio_attachable/dropbox/bootstrap_controller"

class DropboxApplicationControllerTest < ActionController::TestCase
  tests RecordingStudioAttachable::Dropbox::ImportsController

  FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    RecordingStudioAttachable.configuration.dropbox.merge!(enabled: true, client_id: "client-id")

    @controller = RecordingStudioAttachable::Dropbox::ImportsController.new
    @controller.define_singleton_method(:authorize_attachment_action!) { |_action, _recording, capability_options: {}| true }
    @controller.define_singleton_method(:capability_options_for) { |_recording| {} }
    @controller.define_singleton_method(:current_attachable_actor) { :actor }
    ensure_recording_lookup!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_ensure_dropbox_enabled_requires_the_addon_to_be_enabled
    RecordingStudioAttachable.configuration.dropbox.enabled = false
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    stub_upload_redirect!

    with_routing do |set|
      set.draw do
        get "/dropbox/recordings/:recording_id/imports",
            to: "recording_studio_attachable/dropbox/imports#index"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        get :index, params: { recording_id: recording.id }
      end
    end

    assert_redirected_to "/recordings/rec-1/attachment_upload"
    assert_equal "Dropbox isn't available right now", flash[:alert]
  end

  def test_ensure_dropbox_enabled_requires_the_dropbox_gem
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    stub_upload_redirect!

    with_routing do |set|
      set.draw do
        get "/dropbox/recordings/:recording_id/imports",
            to: "recording_studio_attachable/dropbox/imports#index"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        RecordingStudioAttachable::Dropbox::Integration.stub(:gem_loaded?, false) do
          get :index, params: { recording_id: recording.id }
        end
      end
    end

    assert_redirected_to "/recordings/rec-1/attachment_upload"
    assert_equal "Dropbox isn't available right now", flash[:alert]
  end

  def test_ensure_dropbox_chooser_configured_requires_an_app_key
    RecordingStudioAttachable.configuration.dropbox.client_id = nil
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    use_bootstrap_controller!

    with_routing do |set|
      set.draw do
        get "/dropbox/recordings/:recording_id/bootstrap(.:format)",
            to: "recording_studio_attachable/dropbox/bootstrap#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        DropboxFakes.with_gem_loaded do
          get :show, params: { recording_id: recording.id, format: :json }
        end
      end
    end

    assert_response :unprocessable_content
    assert_equal "Dropbox Chooser needs an app key", JSON.parse(@response.body).fetch("error")
  end

  def test_ensure_dropbox_chooser_configured_rejects_dummy_placeholder_values
    RecordingStudioAttachable.configuration.dropbox.client_id = "dummy-dropbox-client-id"
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    use_bootstrap_controller!

    with_routing do |set|
      set.draw do
        get "/dropbox/recordings/:recording_id/bootstrap(.:format)",
            to: "recording_studio_attachable/dropbox/bootstrap#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        DropboxFakes.with_gem_loaded do
          get :show, params: { recording_id: recording.id, format: :json }
        end
      end
    end

    assert_response :unprocessable_content
    assert_equal "Dropbox Chooser needs an app key", JSON.parse(@response.body).fetch("error")
  end

  def test_dropbox_connected_uses_oauth_connection_not_session
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    @controller.define_singleton_method(:dropbox_oauth_connect_path) { "/recording_studio_oauth/outbound/dropbox/connect" }
    @controller.define_singleton_method(:dropbox) do
      Object.new.tap do |proxy|
        proxy.define_singleton_method(:recording_imports_path) do |record, **kwargs|
          "/dropbox/recordings/#{record.id}/imports?#{kwargs.compact.to_query}"
        end
        proxy.define_singleton_method(:recording_connected_path) do |record, **kwargs|
          "/dropbox/recordings/#{record.id}/connected?#{kwargs.compact.to_query}"
        end
      end
    end

    with_routing do |set|
      set.draw do
        get "/dropbox/recordings/:recording_id/imports",
            to: "recording_studio_attachable/dropbox/imports#index"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        DropboxFakes.with_gem_loaded do
          RecordingStudioAttachable::Dropbox::Integration.stub(:connection, nil) do
            @controller.stub(:render, lambda { |*_, **kwargs|
              @controller.response_body = [
                [@controller.instance_variable_get(:@show_connect), @request.session["recording_studio_attachable_dropbox"]].join(" ")
              ]
              @controller.status = kwargs[:status] || :ok
            }) do
              get :index, params: { recording_id: recording.id }
            end
          end
        end
      end
    end

    assert_response :success
    assert_equal "true ", @response.body
    assert_nil @request.session["recording_studio_attachable_dropbox"]
  end

  def test_dependency_unavailable_alert_redirects_to_attachment_upload_path
    RecordingStudioAttachable.configuration.dropbox.enabled = false
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    stub_upload_redirect!

    with_routing do |set|
      set.draw do
        get "/dropbox/recordings/:recording_id/imports",
            to: "recording_studio_attachable/dropbox/imports#index"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        get :index, params: { recording_id: recording.id }
      end
    end

    assert_redirected_to "/recordings/rec-1/attachment_upload"
    assert_equal "Dropbox isn't available right now", flash[:alert]
  end

  private

  def use_bootstrap_controller!
    @controller = RecordingStudioAttachable::Dropbox::BootstrapController.new
    @controller.define_singleton_method(:authorize_attachment_action!) { |_action, _recording, capability_options: {}| true }
    @controller.define_singleton_method(:capability_options_for) { |_recording| {} }
    @controller.define_singleton_method(:current_attachable_actor) { :actor }
  end

  def stub_upload_redirect!
    upload_proxy = Object.new
    upload_proxy.define_singleton_method(:recording_attachment_upload_path) do |record, _options = {}|
      "/recordings/#{record.id}/attachment_upload"
    end
    @controller.define_singleton_method(:recording_studio_attachable) { upload_proxy }
  end

  def ensure_recording_lookup!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)

    return if RecordingStudio::Recording.respond_to?(:find)

    RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
  end
end
