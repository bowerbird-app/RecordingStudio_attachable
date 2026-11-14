# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/attachment_lifecycle_controller"
require_relative "../lib/recording_studio_attachable/services/base_service"
require_relative "../app/services/recording_studio_attachable/services/application_service"
require_relative "../app/services/recording_studio_attachable/services/remove_attachment"
require_relative "../app/services/recording_studio_attachable/services/remove_attachments"
require_relative "../app/services/recording_studio_attachable/services/restore_attachment"

module RecordingStudioAttachable
  class AttachmentLifecycleRequestsTest < ActionController::TestCase
    tests AttachmentLifecycleController

    FakeRecording = Struct.new(:id, :recordable_type, :parent_recording, keyword_init: true)

    def setup
      @controller = AttachmentLifecycleController.new
      @routes = draw_routes
      @controller.define_singleton_method(:recording_attachments_path) do |recording, options = {}|
        query = options.compact_blank.to_query
        path = "/recordings/#{recording.id}/attachments"
        query.present? ? "#{path}?#{query}" : path
      end
      @controller.define_singleton_method(:attachment_path) do |recording|
        "/attachments/#{recording.id}"
      end
      @controller.define_singleton_method(:main_app) do
        app = Object.new
        app.define_singleton_method(:root_path) { "/" }
        app
      end
    end

    def test_bulk_remove_reports_the_count_and_keeps_the_library_filters
      parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
      result = Services::BaseService::Result.new(success: true, value: %w[one two])

      with_recording(parent) do
        @controller.stub(:authorize_attachment_action!, true) do
          Services::RemoveAttachments.stub(:call, ->(**) { result }) do
            post :bulk_destroy, params: {
              recording_id: parent.id,
              attachment_ids: %w[one two],
              scope: "direct",
              kind: "image",
              q: "",
              page: "2"
            }
          end
        end
      end

      assert_redirected_to "/recordings/parent-1/attachments?kind=image&page=2&scope=direct"
      assert_equal "Removed 2 attachment(s).", flash[:notice]
    end

    def test_bulk_remove_shows_the_service_error
      parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
      result = Services::BaseService::Result.new(success: false, error: "Select at least one attachment to remove")

      with_recording(parent) do
        @controller.stub(:authorize_attachment_action!, true) do
          Services::RemoveAttachments.stub(:call, ->(**) { result }) do
            post :bulk_destroy, params: { recording_id: parent.id, attachment_ids: [] }
          end
        end
      end

      assert_redirected_to "/recordings/parent-1/attachments"
      assert_equal "Select at least one attachment to remove", flash[:alert]
    end

    def test_destroy_shows_the_service_error
      attachment = FakeRecording.new(id: "att-1", recordable_type: "RecordingStudioAttachable::Attachment")
      parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
      result = Services::BaseService::Result.new(success: false, error: "Attachment could not be removed")

      with_recording(attachment) do
        @controller.stub(:authorize_attachment_owner_action!, true) do
          @controller.stub(:attachable_owner_recording, parent) do
            Services::RemoveAttachment.stub(:call, ->(**) { result }) do
              delete :destroy, params: { id: attachment.id }
            end
          end
        end
      end

      assert_redirected_to "/recordings/parent-1/attachments"
      assert_equal "Attachment could not be removed", flash[:alert]
    end

    def test_destroy_without_a_parent_returns_home
      attachment = FakeRecording.new(id: "att-1", recordable_type: "RecordingStudioAttachable::Attachment")
      result = Services::BaseService::Result.new(success: true, value: attachment)

      with_recording(attachment) do
        @controller.stub(:authorize_attachment_owner_action!, true) do
          @controller.stub(:attachable_owner_recording, nil) do
            Services::RemoveAttachment.stub(:call, ->(**) { result }) do
              delete :destroy, params: { id: attachment.id }
            end
          end
        end
      end

      assert_redirected_to "/"
      assert_equal "Attachment removed.", flash[:notice]
    end

    def test_restore_reports_success_and_failure
      attachment = FakeRecording.new(id: "att-1", recordable_type: "RecordingStudioAttachable::Attachment")
      success = Services::BaseService::Result.new(success: true, value: attachment)
      failure = Services::BaseService::Result.new(success: false, error: "Attachment could not be restored")

      with_recording(attachment) do
        @controller.stub(:authorize_attachment_owner_action!, true) do
          Services::RestoreAttachment.stub(:call, ->(**) { success }) do
            post :restore, params: { id: attachment.id }
          end
        end
      end
      assert_redirected_to "/attachments/att-1"
      assert_equal "Attachment restored.", flash[:notice]

      with_recording(attachment) do
        @controller.stub(:authorize_attachment_owner_action!, true) do
          Services::RestoreAttachment.stub(:call, ->(**) { failure }) do
            post :restore, params: { id: attachment.id }
          end
        end
      end
      assert_redirected_to "/attachments/att-1"
      assert_equal "Attachment could not be restored", flash[:alert]
    end

    def test_a_denied_remove_redirects_html_and_forbids_json
      parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
      attachment = FakeRecording.new(
        id: "att-1",
        recordable_type: "RecordingStudioAttachable::Attachment",
        parent_recording: parent
      )
      ensure_accessible!

      with_recording(attachment) do
        with_denied_accessible do
          delete :destroy, params: { id: attachment.id }
        end
      end

      assert_redirected_to "/"
      assert_match(/Not authorized to remove/, flash[:alert])

      with_recording(attachment) do
        with_denied_accessible do
          delete :destroy, params: { id: attachment.id }, as: :json
        end
      end

      assert_response :forbidden
      assert_match(/Not authorized to remove/, JSON.parse(response.body).fetch("error"))
    end

    def test_a_missing_attachment_redirects_html_and_returns_not_found_json
      missing = FakeRecording.new(id: "missing", recordable_type: "Workspace")

      with_recording(missing) do
        delete :destroy, params: { id: missing.id }
      end
      assert_redirected_to "/"
      assert_equal "Attachment resource not found", flash[:alert]

      with_recording(missing) do
        delete :destroy, params: { id: missing.id }, as: :json
      end
      assert_response :not_found
      assert_equal "Not found", JSON.parse(response.body).fetch("error")
    end

    def test_an_invalid_return_to_does_not_leave_the_library
      parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
      attachment = FakeRecording.new(id: "att-1", recordable_type: "RecordingStudioAttachable::Attachment")
      result = Services::BaseService::Result.new(success: true, value: attachment)

      with_recording(attachment) do
        @controller.stub(:authorize_attachment_owner_action!, true) do
          @controller.stub(:attachable_owner_recording, parent) do
            Services::RemoveAttachment.stub(:call, ->(**) { result }) do
              delete :destroy, params: { id: attachment.id, redirect_mode: "return_to", return_to: "http://[" }
            end
          end
        end
      end

      assert_redirected_to "/recordings/parent-1/attachments"
    end

    private

    def draw_routes
      routes = ActionDispatch::Routing::RouteSet.new
      routes.draw do
        post "/recordings/:recording_id/attachments/bulk_remove",
             to: "recording_studio_attachable/attachment_lifecycle#bulk_destroy"
        delete "/attachments/:id", to: "recording_studio_attachable/attachment_lifecycle#destroy"
        post "/attachments/:id/restore", to: "recording_studio_attachable/attachment_lifecycle#restore"
      end
      @controller.instance_variable_set(:@_routes, routes)
      routes
    end

    def with_recording(recording, &block)
      ensure_recording_lookup!
      @controller.stub(:protect_against_forgery?, false) do
        RecordingStudio::Recording.stub(:find, lambda { |id|
          raise ActiveRecord::RecordNotFound unless id.to_s == recording.id.to_s

          recording
        }) do
          block.call
        end
      end
    end

    def ensure_recording_lookup!
      studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
      studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)
      return if RecordingStudio::Recording.respond_to?(:find)

      RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise ActiveRecord::RecordNotFound }
    end

    def ensure_accessible!
      return if defined?(RecordingStudioAccessible::Authorization)

      Object.const_set(:RecordingStudioAccessible, Module.new) unless defined?(RecordingStudioAccessible)
      RecordingStudioAccessible.const_set(:Authorization, Module.new)
      RecordingStudioAccessible::Authorization.define_singleton_method(:allowed?) { |**| false }
    end

    def with_denied_accessible(&block)
      RecordingStudio.configuration.stub(:capability_enabled?, true) do
        RecordingStudioAccessible::Authorization.stub(:allowed?, ->(**) { false }) do
          block.call
        end
      end
    end
  end
end
