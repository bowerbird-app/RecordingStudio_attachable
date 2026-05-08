# frozen_string_literal: true

require "test_helper"
require_relative "dummy/app/models/current"

module ActionController
  class Base
    def self.allow_browser(...) = nil

    def self.stale_when_importmap_changes = nil
  end
end

require_relative "dummy/app/controllers/application_controller"
require_relative "dummy/app/controllers/chat_demo_controller"

class ChatDemoControllerTest < ActionController::TestCase
  class FakeAttachmentCollection
    attr_reader :built_attachment_recordings

    def initialize
      @built_attachment_recordings = []
    end

    def build(attachment_recording:)
      @built_attachment_recordings << attachment_recording
    end
  end

  class FakeSentMessage
    attr_reader :chat_message_attachments
    attr_accessor :saved

    def initialize
      @chat_message_attachments = FakeAttachmentCollection.new
      @saved = false
    end

    def save!
      @saved = true
    end
  end

  class FakeChatMessages
    attr_reader :created_attributes

    def initialize(sent_message, events)
      @sent_message = sent_message
      @events = events
    end

    def new(attributes)
      @created_attributes = attributes
      @events << :build_sent_message
      @sent_message
    end
  end

  class FakeDraftMessage
    def self.transaction
      yield
    end

    attr_reader :chat_thread, :direction, :position, :attachment_recordings

    def initialize(chat_thread:, direction:, position:, attachment_recordings:)
      @chat_thread = chat_thread
      @direction = direction
      @position = position
      @attachment_recordings = attachment_recordings
    end
  end

  def setup
    @controller = ChatDemoController.new
  end

  def test_create_strips_body_and_delegates_to_snapshot_send
    draft_message = Object.new
    captured = nil

    with_routing do |set|
      set.draw do
        post "/chat/demo/messages", to: "chat_demo#create"
        get "/chat/demo", to: "chat_demo#show"
      end

      @routes = set
      @controller.define_singleton_method(:authenticate_user!) { true }
      @controller.define_singleton_method(:set_current_actor) { true }

      @controller.stub(:set_workspace_context, true) do
        @controller.stub(:set_chat_thread_context, true) do
          @controller.stub(:find_draft_message!, lambda { |id|
            assert_equal "draft-1", id
            draft_message
          }) do
            @controller.stub(:send_draft_message!, lambda { |message, body|
              captured = [message, body]
            }) do
              @controller.stub(:protect_against_forgery?, false) do
                post :create, params: {
                  chat_demo: {
                    draft_message_id: "draft-1",
                    body: "  This seeded chat thread appears in the recording tree.  "
                  }
                }
              end
            end
          end
        end
      end
    end

    assert_redirected_to "/chat/demo"
    assert_equal [draft_message, "This seeded chat thread appears in the recording tree."], captured
  end

  def test_send_draft_message_builds_attachment_only_sent_snapshot_before_saving
    events = []
    sent_message = FakeSentMessage.new
    chat_messages = FakeChatMessages.new(sent_message, events)
    chat_thread = Struct.new(:chat_messages).new(chat_messages)
    attachment_a = Object.new
    attachment_b = Object.new
    draft_message = FakeDraftMessage.new(
      chat_thread: chat_thread,
      direction: "outgoing",
      position: 3,
      attachment_recordings: [attachment_a, attachment_b]
    )
    recorded = nil

    @controller.stub(:ensure_message_recording!, ->(message) { recorded = message }) do
      @controller.stub(:destroy_message!, lambda { |message|
        events << :destroy_draft
        assert_same draft_message, message
      }) do
        result = @controller.send(:send_draft_message!, draft_message, nil)

        assert_same sent_message, result
      end
    end

    assert_equal(
      {
        body: nil,
        direction: "outgoing",
        position: 3,
        status: "sent",
        sent_at: chat_messages.created_attributes[:sent_at]
      },
      chat_messages.created_attributes
    )
    assert_instance_of Time, chat_messages.created_attributes[:sent_at]
    assert_equal %i[destroy_draft build_sent_message], events
    assert_equal [attachment_a, attachment_b], sent_message.chat_message_attachments.built_attachment_recordings
    assert sent_message.saved
    assert_same sent_message, recorded
  end
end
