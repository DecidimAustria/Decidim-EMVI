# frozen_string_literal: true

require "decidim/maintenance"

module Emvi
  # 0.30.9 maintenance-only fixes: retain filters from earlier import sections
  # and match component filters consistently when the plan omits manifests.
  # Keep the nonempty import regression tests when moving to another release.
  module TaxonomyImportCompatibility
    private

    def import_filter(root, data)
      previous_filters = data.fetch("components", []).filter_map do |gid|
        component = GlobalID::Locator.locate(gid)
        [component, Array(component.settings.taxonomy_filters).map(&:to_s), gid] if component
      end
      super
      previous_filters.each do |component, previous, gid|
        next if result[:failed_components].include?(gid)

        current = Array(component.reload.settings.taxonomy_filters).map(&:to_s)
        combined = previous | current
        component.update!(settings: component.settings.to_h.merge(taxonomy_filters: combined)) unless combined == current
      end
    end

    def find_taxonomy_filter(root_taxonomy, name:, participatory_space_manifests:)
      super(root_taxonomy, name: name, participatory_space_manifests: Array(participatory_space_manifests))
    end
  end
end

if Gem.loaded_specs.fetch("decidim-core").version.to_s == "0.30.9"
  Decidim::Maintenance::TaxonomyImporter.prepend(Emvi::TaxonomyImportCompatibility)
end
