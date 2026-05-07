class Workspace < ApplicationRecord
  include RecordingStudio::Capabilities::Attachable.to(
    allowed_content_types: [ "image/*", "application/pdf", "text/plain" ],
    max_file_size: 1.megabyte,
    enabled_attachment_kinds: %i[ image file ]
  )
end
