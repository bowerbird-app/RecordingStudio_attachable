module ApplicationHelper
  def build_recording_tree_nodes(tree, recordings, recording_children)
    recordings.each do |recording|
      children = Array(recording_children[recording.id])

      tree.node(label: recording_tree_label(recording), icon: recording_tree_icon(recording), expanded: children.any?) do |branch|
        build_recording_tree_nodes(branch, children, recording_children)
      end
    end
  end

  def recording_tree_icon(recording)
    case recording.recordable_type.to_s.demodulize
    when "Access", "AccessBoundary"
      :lock
    when "Attachment"
      recording.recordable.image? ? :image : :file
    when "Page"
      "document-text"
    end
  end

  def recording_tree_label(recording)
    recordable = recording.recordable
    recordable_name =
      if recordable.respond_to?(:title) && recordable.title.present?
        recordable.title
      elsif recordable.respond_to?(:name) && recordable.name.present?
        recordable.name
      elsif recordable.respond_to?(:email) && recordable.email.present?
        recordable.email
      else
        recordable.class.name.demodulize
      end

    "#{recording.recordable_type.demodulize}: #{recordable_name}"
  end
end
