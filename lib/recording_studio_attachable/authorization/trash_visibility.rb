# frozen_string_literal: true

module RecordingStudioAttachable
  module Authorization
    module TrashVisibility
      module_function

      def hidden?(recording)
        return false unless defined?(::RecordingStudioTrashable)
        return false unless recording.respond_to?(:trashed_at)

        trashed_node?(recording, {})
      end

      def trashed_node?(node, seen)
        return false if stop?(node, seen)

        seen[marker(node)] = true
        return true if node.trashed_at.present?

        trashed_node?(parent_of(node), seen)
      end

      def stop?(node, seen)
        node.nil? || root?(node) || seen[marker(node)]
      end

      def root?(recording)
        recording.respond_to?(:parent_recording_id) && recording.parent_recording_id.nil?
      end

      def parent_of(node)
        return unless node.respond_to?(:parent_recording)

        node.parent_recording
      end

      def marker(node)
        node.respond_to?(:id) ? node.id : node.object_id
      end
      private_class_method :trashed_node?, :stop?, :root?, :parent_of, :marker
    end
  end
end
