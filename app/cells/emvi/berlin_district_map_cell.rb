# frozen_string_literal: true

module Emvi
  class BerlinDistrictMapCell < Decidim::ViewModel
    def show
      return "" unless Emvi::BerlinDistrictMap.organization?(current_organization) &&
                       Emvi::BerlinDistrictMap.organization?(model.organization) &&
                       model.scope_name == "homepage" &&
                       model.manifest_name == Emvi::BerlinDistrictMap::MANIFEST

      render
    end

    def title
      translated_attribute(model.settings.title)
    end

    def introduction
      decidim_sanitize_editor_admin(translated_attribute(model.settings.introduction))
    end
  end
end
