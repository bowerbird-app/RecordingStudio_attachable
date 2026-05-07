# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/attachments_controller"
require_relative "../app/controllers/recording_studio_attachable/attachment_uploads_controller"
require_relative "../lib/recording_studio_attachable/services/base_service"
require_relative "../app/services/recording_studio_attachable/services/application_service"
require_relative "../app/services/recording_studio_attachable/services/record_attachment_uploads"

module RecordingStudioAttachable
  class AttachmentUploadsControllerTest < ActionController::TestCase
    FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)

    def setup
      ensure_recording_lookup!
    end

    def test_attachment_payloads_permits_nested_json_attachment_fields
      @controller = AttachmentUploadsController.new
      @controller.send(
        :params=,
        ActionController::Parameters.new(
          attachments: [
            {
              signed_blob_id: "blob-1",
              name: "bike rack plans",
              description: ""
            }
          ],
          attachment_upload: {
            attachments: [
              {
                signed_blob_id: "blob-1",
                name: "bike rack plans",
                description: "",
                ignored: "value"
              }
            ]
          }
        )
      )

      assert_equal(
        [{ signed_blob_id: "blob-1", name: "bike rack plans", description: "" }],
        @controller.send(:attachment_payloads)
      )
    end

    def test_new_assigns_configured_upload_providers
      @controller = AttachmentUploadsController.new
      recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
      provider = RecordingStudioAttachable::UploadProvider.new(
        key: :google_drive,
        label: "Google Drive",
        url: "/imports/google_drive"
      )

      with_routing do |set|
        set.draw do
          get "/recordings/:recording_id/attachments/upload",
              to: "recording_studio_attachable/attachment_uploads#new"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, recording) do
          @controller.stub(:authorize_attachment_action!, true) do
            @controller.stub(:capability_options_for, {}) do
              configured_option = lambda { |_recording, option_name|
                {
                  allowed_content_types: ["image/*"],
                  max_file_size: 25.megabytes,
                  max_file_count: 20,
                  image_processing_enabled: true,
                  image_processing_max_width: 2048,
                  image_processing_max_height: 2048,
                  image_processing_quality: 0.8
                }.fetch(option_name)
              }

              @controller.stub(:configured_attachable_option, configured_option) do
                @controller.stub(:configured_upload_providers, [provider]) do
                  @controller.define_singleton_method(:recording_attachments_path) do |_recording, query_params = {}|
                    suffix = query_params.to_h.to_query
                    suffix.present? ? "/recordings/#{recording.id}/attachments?#{suffix}" : "/recordings/#{recording.id}/attachments"
                  end
                  @controller.define_singleton_method(:default_render) do
                    render plain: Array(@upload_providers).map(&:label).join(",")
                  end
                  get :new, params: { recording_id: recording.id }
                end
              end
            end
          end
        end
      end

      assert_response :success
      assert_equal "Google Drive", @response.body
    end

    def test_show_assigns_replacement_image_processing_options
      @controller = AttachmentsController.new
      recording = FakeRecording.new(id: "rec-1", recordable_type: "RecordingStudioAttachable::Attachment")
      attachment = Struct.new(:name, :description, :original_filename).new("Hero", "", "hero.png")
      recording.define_singleton_method(:recordable) { attachment }

      with_routing do |set|
        set.draw do
          get "/attachments/:id", to: "recording_studio_attachable/attachments#show"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, recording) do
          @controller.stub(:authorize_attachment_owner_action!, true) do
            configured_option = lambda { |_recording, option_name|
              {
                allowed_content_types: ["image/*"],
                max_file_size: 25.megabytes,
                image_processing_enabled: true,
                image_processing_max_width: 1600,
                image_processing_max_height: 1200,
                image_processing_quality: 0.72
              }.fetch(option_name)
            }

            @controller.stub(:configured_attachable_option, configured_option) do
              @controller.stub(:attachable_owner_recording, nil) do
                @controller.define_singleton_method(:default_render) do
                  render plain: [
                    @image_processing_enabled,
                    @image_processing_max_width,
                    @image_processing_max_height,
                    @image_processing_quality
                  ].join(":")
                end

                get :show, params: { id: recording.id }
              end
            end
          end
        end
      end

      assert_response :success
      assert_equal "true:1600:1200:0.72", @response.body
    end

    def test_new_resolves_a_mounted_provider_button_url
      recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
      provider = RecordingStudioAttachable::UploadProvider.new(
        key: :mounted_provider,
        label: "Mounted provider",
        url: ->(route_helpers:, recording:) { route_helpers.mounted_provider.recording_imports_path(recording) }
      )
      mounted_proxy = Object.new
      mounted_proxy.define_singleton_method(:recording_imports_path) { |record| "/mounted_provider/recordings/#{record.id}/imports" }
      view_context = Object.new
      view_context.define_singleton_method(:mounted_provider) { mounted_proxy }

      assert_equal(
        {
          text: "Mounted provider",
          style: :secondary,
          size: :md,
          url: "/mounted_provider/recordings/rec-1/imports",
          icon: "cloud"
        },
        provider.button_options(view_context: view_context, recording: recording)
      )
    end

    def test_create_passes_nil_impersonator_when_current_does_not_define_it
      @controller = AttachmentUploadsController.new
      recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
      original_current = Object.send(:remove_const, :Current) if defined?(Current)
      current = Object.const_set(:Current, Class.new)
      captured = nil

      current.define_singleton_method(:actor) { :actor }

      RecordingStudio::Recording.define_singleton_method(:find) { |_id| recording }

      with_routing do |set|
        set.draw do
          post "/recordings/:recording_id/attachments",
               to: "recording_studio_attachable/attachment_uploads#create"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, recording) do
          @controller.stub(:authorize_attachment_action!, true) do
            @controller.stub(:capability_options_for, {}) do
              @controller.define_singleton_method(:recording_attachments_path) do |_recording, query_params = {}|
                suffix = query_params.to_h.to_query
                suffix.present? ? "/recordings/#{recording.id}/attachments?#{suffix}" : "/recordings/#{recording.id}/attachments"
              end
              @controller.stub(:recording_attachments_path, "/recordings/#{recording.id}/attachments") do
                result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [])
                def test_new_preserves_safe_referer_as_return_to_when_redirect_mode_is_referer
                  @controller = AttachmentUploadsController.new
                  recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")

                  with_routing do |set|
                    set.draw do
                      get "/recordings/:recording_id/attachments/upload",
                          to: "recording_studio_attachable/attachment_uploads#new"
                    end

                    @routes = set

                    RecordingStudio::Recording.stub(:find, recording) do
                      @controller.stub(:authorize_attachment_action!, true) do
                        @controller.stub(:capability_options_for, {}) do
                          configured_option = lambda { |_recording, option_name|
                            {
                              allowed_content_types: ["image/*"],
                              max_file_size: 25.megabytes,
                              max_file_count: 20,
                              image_processing_enabled: true,
                              image_processing_max_width: 2048,
                              image_processing_max_height: 2048,
                              image_processing_quality: 0.8
                            }.fetch(option_name)
                          }

                          @controller.stub(:configured_attachable_option, configured_option) do
                            @controller.stub(:configured_upload_providers, []) do
                              @controller.define_singleton_method(:recording_attachments_path) do |_recording, query_params = {}|
                                suffix = query_params.to_h.to_query
                                suffix.present? ? "/recordings/#{recording.id}/attachments?#{suffix}" : "/recordings/#{recording.id}/attachments"
                              end
                              @controller.define_singleton_method(:default_render) do
                                render plain: @create_path
                              end
                              @request.env["HTTP_REFERER"] = "http://test.host/pages/page-1#hero-image"
                              get :new, params: { recording_id: recording.id, redirect_mode: "referer" }
                            end
                          end
                        end
                      end
                    end
                  end

                  assert_response :success
                  assert_equal "/recordings/rec-1/attachments?redirect_mode=referer&return_to=%2Fpages%2Fpage-1%23hero-image", @response.body
                end

                def test_create_redirects_to_explicit_return_to_when_requested
                  @controller = AttachmentUploadsController.new
                  recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
                  result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [Object.new])

                  with_routing do |set|
                    set.draw do
                      post "/recordings/:recording_id/attachments",
                           to: "recording_studio_attachable/attachment_uploads#create"
                    end

                    @routes = set

                    RecordingStudio::Recording.stub(:find, recording) do
                      @controller.stub(:authorize_attachment_action!, true) do
                        @controller.stub(:capability_options_for, {}) do
                          @controller.define_singleton_method(:recording_attachments_path) do |_recording, query_params = {}|
                            suffix = query_params.to_h.to_query
                            suffix.present? ? "/recordings/#{recording.id}/attachments?#{suffix}" : "/recordings/#{recording.id}/attachments"
                          end

                          RecordingStudioAttachable::Services::RecordAttachmentUploads.stub(:call, result) do
                            @controller.stub(:protect_against_forgery?, false) do
                              post :create,
                                   params: {
                                     recording_id: recording.id,
                                     redirect_mode: "return_to",
                                     return_to: "/pages/page-1#hero-image",
                                     attachments: [{ signed_blob_id: "blob-1", name: "one", description: "" }]
                                   }
                            end
                          end
                        end
                      end
                    end
                  end

                  assert_redirected_to "/pages/page-1#hero-image"
                end

                def test_create_falls_back_to_library_for_unsafe_return_to
                  @controller = AttachmentUploadsController.new
                  recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
                  result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [Object.new])

                  with_routing do |set|
                    set.draw do
                      post "/recordings/:recording_id/attachments",
                           to: "recording_studio_attachable/attachment_uploads#create"
                    end

                    @routes = set

                    RecordingStudio::Recording.stub(:find, recording) do
                      @controller.stub(:authorize_attachment_action!, true) do
                        @controller.stub(:capability_options_for, {}) do
                          @controller.define_singleton_method(:recording_attachments_path) do |_recording, query_params = {}|
                            suffix = query_params.to_h.to_query
                            suffix.present? ? "/recordings/#{recording.id}/attachments?#{suffix}" : "/recordings/#{recording.id}/attachments"
                          end

                          RecordingStudioAttachable::Services::RecordAttachmentUploads.stub(:call, result) do
                            @controller.stub(:protect_against_forgery?, false) do
                              post :create,
                                   params: {
                                     recording_id: recording.id,
                                     redirect_mode: "return_to",
                                     return_to: "https://evil.example/steal",
                                     attachments: [{ signed_blob_id: "blob-1", name: "one", description: "" }]
                                   },
                                   as: :json
                            end
                          end
                        end
                      end
                    end
                  end

                  assert_response :created
                  assert_equal "/recordings/rec-1/attachments", JSON.parse(@response.body).fetch("redirect_path")
                end

                RecordingStudioAttachable::Services::RecordAttachmentUploads.stub(:call, lambda { |**kwargs|
                  captured = kwargs
                  result
                }) do
                  @controller.stub(:protect_against_forgery?, false) do
                    post :create,
                         params: { recording_id: recording.id, attachments: [{ signed_blob_id: "blob-1", name: "one", description: "" }] },
                         as: :json
                  end
                end
              end
            end
          end
        end
      end

      assert_response :created
      assert_equal :actor, captured[:actor]
      assert_nil captured[:impersonator]
      assert_equal recording, captured[:parent_recording]
      assert_equal [{ signed_blob_id: "blob-1", name: "one", description: "" }], captured[:attachments]
    ensure
      current.singleton_class.send(:remove_method, :actor) if current.respond_to?(:actor)
      Object.send(:remove_const, :Current) if defined?(Current)
      Object.const_set(:Current, original_current) if original_current
    end

    private

    def ensure_current_class
      return Current if defined?(Current)

      Object.const_set(:Current, Class.new)
    end

    def ensure_recording_lookup!
      studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
      studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)

      return if RecordingStudio::Recording.respond_to?(:find)

      RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
    end
  end
end
