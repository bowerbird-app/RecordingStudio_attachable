class Page < ApplicationRecord
  include RecordingStudio::Capabilities::Attachable.to(
    allowed_content_types: [ "image/*" ],
    max_file_size: 25.megabytes,
    enabled_attachment_kinds: %i[ image ]
  )
end
