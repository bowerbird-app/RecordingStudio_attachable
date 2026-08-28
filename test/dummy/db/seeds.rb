# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

def seed_avery_profile_photo!(user_recording, user)
  existing = user_recording.images(scope: :direct).first
  if existing
    attachment = existing.recordable
    return if attachment.byte_size > 1_000 && attachment.previewable?

    user_recording.remove_attachments(
      attachment_recordings: [existing],
      actor: user
    )
  end

  fixture_path = Rails.root.join("db/fixtures/files/avery_profile.png")
  return unless fixture_path.exist?

  File.open(fixture_path, "rb") do |io|
    result = RecordingStudioAttachable::Services::ImportAttachment.call(
      parent_recording: user_recording,
      io: io,
      filename: "avery_profile.png",
      content_type: "image/png",
      actor: user,
      name: "Profile photo"
    )
    raise result.error if result.failure?
  end

  puts "Seeded: Avery profile photo on user recording ##{user_recording.id}"
end

# Create the admin user
admin_email = "admin@admin.com"
admin_password = "Password"

user = User.find_or_initialize_by(email: admin_email)

unless user.persisted? && user.valid_password?(admin_password)
  user.password = admin_password
  user.password_confirmation = admin_password
end

user.name = "Avery" if user.name.blank?

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
Current.actor = user
root_recording = RecordingStudio.root_recording_for(workspace)

RecordingStudio::Recording.unscoped.find_or_create_by!(
  root_recording_id: root_recording.id,
  parent_recording_id: root_recording.id,
  recordable: page
)

user_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(
  root_recording_id: root_recording.id,
  parent_recording_id: root_recording.id,
  recordable: user
)

seed_avery_profile_photo!(user_recording, user)

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
original_access_authorizer = RecordingStudioAccessible.configuration.access_management_authorizer
RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
begin
  grant_result = RecordingStudioAccessible.grant_access(
    recording: root_recording,
    actor: user,
    role: :admin,
    manager_actor: user
  )
  raise grant_result.error if grant_result.failure?
ensure
  RecordingStudioAccessible.configuration.access_management_authorizer = original_access_authorizer
end

puts "Seeded: #{admin_email} / #{admin_password}"
puts "Seeded: Workspace '#{workspace.name}' with root recording ##{root_recording.id}"
puts "Seeded: Page '#{page.title}' beneath the workspace root recording"
puts "Seeded: User '#{user.name}' beneath the workspace root recording"
puts "Seeded: Chat thread '#{chat_thread.title}' with #{chat_messages.count} recorded messages"
