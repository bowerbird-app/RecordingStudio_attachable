module ApplicationHelper
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
