# frozen_string_literal: true

Decidim.content_blocks.register(:homepage, :berlin_district_map) do |block|
  block.cell = "emvi/berlin_district_map"
  block.public_name_key = "emvi.berlin_district_map.name"
  block.settings_form_cell = "emvi/berlin_district_map_settings_form"
  block.settings do |settings|
    settings.attribute :title, type: :text, translated: true
    settings.attribute :introduction, type: :text, translated: true
  end
end

Rails.application.config.to_prepare do
  Decidim::Admin::OrganizationHomepageController.prepend(Emvi::BerlinDistrictMap::HomepageManifests)
  Decidim::Admin::ContentBlocks::CreateContentBlock.prepend(Emvi::BerlinDistrictMap::CreateGuard)
end
