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

RecordingStudio::Recording.unscoped.find_or_create_by!(
  root_recording_id: root_recording.id,
  parent_recording_id: root_recording.id,
  recordable: user
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

press_kit = [
  {
    file: "kiln-canister-open.jpg",
    name: "Kiln canister, open",
    caption: "Lid set aside",
    credit: "Studio North",
    alt_text: "Smoked glass canister with the brass lid resting beside it"
  },
  {
    file: "kiln-canister-detail.jpg",
    name: "Kiln canister, detail",
    caption: "Brass lid",
    credit: "Studio North",
    alt_text: "Close view of the brass lid on the smoked glass canister"
  },
  {
    file: "kiln-canister-table.jpg",
    name: "Kiln canister, table",
    caption: "On the breakfast table",
    credit: "Studio North",
    alt_text: "Smoked glass canister on a linen table beside a cup and napkin"
  },
  {
    file: "kiln-canister-hero.jpg",
    name: "Kiln canister",
    caption: "Hero, three-quarter",
    credit: "Studio North",
    alt_text: "Smoked glass canister with a brass lid on pale limestone"
  }
]
press_kit_dir = Rails.root.join("db/seed_images")
press_kit.each do |shot|
  path = press_kit_dir.join(shot[:file])
  raise "Missing seed image fixture: #{path}" unless path.file?
end

existing_images = root_recording.images(per_page: 100).to_a

%w[window.jpg dock.jpg pier.jpg].each do |filename|
  existing_images.each do |recording|
    next unless recording.recordable.original_filename == filename

    recording.remove_attachment(actor: user)
  end
end

# Re-import when the Active Storage blob is missing from the current service
# (for example after switching between the test Disk root and local storage).
seed_attachment_blob_available = lambda do |recording|
  attachment = recording&.recordable
  next false unless attachment&.file&.attached?

  blob = attachment.file.blob
  blob.service.exist?(blob.key)
rescue StandardError
  false
end

press_kit.each do |shot|
  existing = existing_images.find { |recording| recording.recordable.original_filename == shot[:file] }
  next if existing && seed_attachment_blob_available.call(existing)

  existing&.remove_attachment(actor: user)

  recording = File.open(press_kit_dir.join(shot[:file]), "rb") do |io|
    root_recording.import_attachment(
      io: io,
      filename: shot[:file],
      content_type: "image/jpeg",
      name: shot[:name],
      actor: user,
      source: "press_kit"
    )
  end
  raise "Could not import #{shot[:file]}" if recording.nil?
  raise "Imported #{shot[:file]} but blob is missing from storage" unless seed_attachment_blob_available.call(recording)

  recording.revise_attachment_metadata(
    actor: user,
    caption: shot[:caption],
    credit: shot[:credit],
    alt_text: shot[:alt_text]
  )
end

puts "Seeded: #{admin_email} / #{admin_password}"
puts "Seeded: Workspace '#{workspace.name}' with root recording ##{root_recording.id}"
puts "Seeded: Page '#{page.title}' beneath the workspace root recording"
puts "Seeded: User '#{user.name}' beneath the workspace root recording"
puts "Seeded: Chat thread '#{chat_thread.title}' with #{chat_messages.count} recorded messages"
puts "Seeded: Kiln canister press kit (#{press_kit.size} images) on the workspace"
