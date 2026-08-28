# frozen_string_literal: true

module UsesDefaultLayout
  extend ActiveSupport::Concern

  included do
    layout "flat_pack_sidebar"
  end
end
