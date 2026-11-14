# frozen_string_literal: true

# Unit tests load FlatPack components without booting Rails. Newer FlatPack
# Grid and Card files expect these siblings first. A second require of Card
# raises a superclass mismatch when another test already loaded it.
module FlatPackComponentLoad
  SHARED_EXTRAS = %w[
    app/components/flat_pack/shared/inline_svg.rb
    app/components/flat_pack/shared/breakpoints.rb
    app/components/flat_pack/shared/control_size.rb
    app/components/flat_pack/shared/frame_height.rb
    app/components/flat_pack/shared/flex.rb
  ].freeze

  CARD_EXTRAS = %w[
    app/components/flat_pack/heading/component.rb
    app/components/flat_pack/card/title/component.rb
  ].freeze

  BUTTON_EXTRAS = %w[
    app/components/flat_pack/button/form_submit.rb
  ].freeze

  def self.require_component(root, path)
    require_all(root, BUTTON_EXTRAS) if path.end_with?("button/component.rb")
    require_all(root, SHARED_EXTRAS) if path.end_with?("grid/component.rb") || path.end_with?("card/component.rb")

    if path.end_with?("card/component.rb")
      return if defined?(FlatPack::Card::Component)

      require_all(root, CARD_EXTRAS)
    end

    require File.join(root, path)
  end

  def self.require_all(root, paths)
    paths.each { |extra| require File.join(root, extra) }
  end
end
