# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create the admin user
admin_email = "admin@admin.com"
admin_password = "Password"

user = User.find_or_initialize_by(email: admin_email)

unless user.persisted? && user.valid_password?(admin_password)
  user.password = admin_password
  user.password_confirmation = admin_password
end

user.save! if user.changed?

# Create the workspace recordable
workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
page = Page.find_or_create_by!(title: "Home page")
chat_thread = ChatThread.find_or_create_by!(title: "Workspace conversation")
chat_messages = [
  {
    position: 1,
    direction: "incoming",
    body: "This seeded chat thread appears in the recording tree.",
    sent_at: Time.zone.parse("2026-05-08 09:12:00") || Time.current
  },
  {
    position: 2,
    direction: "outgoing",
    body: "Choose images from the workspace library or upload a new one from the composer.",
    sent_at: Time.zone.parse("2026-05-08 09:13:00") || Time.current
  }
].map do |attributes|
  ChatMessage.find_or_create_by!(chat_thread: chat_thread, position: attributes[:position]) do |message|
    message.direction = attributes[:direction]
    message.body = attributes[:body]
    message.status = "sent"
    message.sent_at = attributes[:sent_at]
    message.seeded = true
  end
end

# Create the root recording
root_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(
  recordable: workspace,
  parent_recording_id: nil
)

RecordingStudio::Recording.unscoped.find_or_create_by!(
  root_recording_id: root_recording.id,
  parent_recording_id: root_recording.id,
  recordable: page
)

chat_thread_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(
  root_recording_id: root_recording.id,
  parent_recording_id: root_recording.id,
  recordable: chat_thread
)

chat_messages.each do |chat_message|
  RecordingStudio::Recording.unscoped.find_or_create_by!(
    root_recording_id: root_recording.id,
    parent_recording_id: chat_thread_recording.id,
    recordable: chat_message
  )
end

# Grant root-level admin access to the admin user
Current.actor = user
access = RecordingStudio::Access.find_or_create_by!(actor: user, role: :admin)
RecordingStudio::Recording.unscoped.find_or_create_by!(
  root_recording_id: root_recording.id,
  parent_recording_id: root_recording.id,
  recordable: access
)

puts "Seeded: #{admin_email} / #{admin_password}"
puts "Seeded: Workspace '#{workspace.name}' with root recording ##{root_recording.id}"
puts "Seeded: Page '#{page.title}' beneath the workspace root recording"
puts "Seeded: Chat thread '#{chat_thread.title}' with #{chat_messages.count} recorded messages"
