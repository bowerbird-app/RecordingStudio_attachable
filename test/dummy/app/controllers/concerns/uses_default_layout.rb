# frozen_string_literal: true

# Prefer RecordingStudio::UsesDefaultLayout (recording_studio/default_layout).
# This thin alias keeps existing `include UsesDefaultLayout` call sites working.
module UsesDefaultLayout
  extend ActiveSupport::Concern

  included do
    include RecordingStudio::UsesDefaultLayout
  end
end
