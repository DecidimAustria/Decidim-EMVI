# frozen_string_literal: true

# Decidim 0.31 reads standard settings directly from ENV. Keep only application
# choices here; in particular, translation was enabled even without CI variables.
Decidim.configure do |config|
  config.available_locales = Decidim::Env.new(
    "DECIDIM_AVAILABLE_LOCALES",
    "bs,ca,cs,de,en,es,fr,hr,it,nl,pl,pt,ro,ru,el,sl,sr-CS,tr-TR,ar-SA,fa-IR,uk,zh-TW"
  ).to_array
  config.enable_machine_translations = Decidim::Env.new("DECIDIM_ENABLE_MACHINE_TRANSLATION", true).present?
  config.machine_translation_service = ENV.fetch("DECIDIM_MACHINE_TRANSLATION_SERVICE", "Decidim::AmazonTranslate::AmazonTranslator")
  config.machine_translation_delay = 0.seconds

  # Without an explicit provider, retain EMVI's existing HERE static maps.
  # Other MAPS_* provider options are handled by Decidim's native ENV support.
  unless ENV["MAPS_STATIC_PROVIDER"].present? || ENV["MAPS_PROVIDER"].present?
    config.maps = {
      provider: :here,
      api_key: ENV["MAPS_API_KEY"],
      static: { url: ENV.fetch("MAPS_STATIC_URL", "https://image.maps.hereapi.com/mia/v3/base/mc/overlay") }
    }
  end

  config.content_security_policies_extra = {
    "img-src": %w(https://cdn.participation.works),
    "connect-src": %w(https://cdn.participation.works https://ma.mitgestalten.jetzt),
    "frame-src": %w(https://www.youtube.com),
    "script-src": %w(https://ma.participation.works https://ma.mitgestalten.jetzt)
  }
end

Decidim.register_assets_path File.expand_path("app/packs", Rails.application.root)
