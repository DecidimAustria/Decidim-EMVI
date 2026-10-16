# frozen_string_literal: true

module Emvi
  # Error pages can retain the translation toggle without a query string.
  # Upstream 0.30.9 calls query.gsub unconditionally in that case.
  # Remove this adapter when upstream handles a nil query.
  module TranslationBarQueryGuard
    def link
      original_url = request.original_url
      return super unless RequestStore.store[:toggle_machine_translations] && URI.parse(original_url).query.nil?

      link_to button_text, original_url, class: "button button__sm button__transparent-secondary"
    end
  end
end

Rails.application.config.to_prepare do
  Decidim::TranslationBarCell.prepend(Emvi::TranslationBarQueryGuard)
end
