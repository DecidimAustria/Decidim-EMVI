# frozen_string_literal: true

module Emvi
  module BerlinDistrictMap
    HOST = "www.berlinmitallengestalten.de"
    MANIFEST = "berlin_district_map"

    def self.organization?(organization)
      organization&.host == HOST
    end

    module HomepageManifests
      private

      def available_manifests
        super.reject { |manifest| manifest.name.to_s == MANIFEST && !BerlinDistrictMap.organization?(current_organization) }
      end
    end

    module CreateGuard
      def call
        if manifest_name.to_s == MANIFEST && (scope.to_s != "homepage" || !BerlinDistrictMap.organization?(organization))
          return broadcast(:invalid)
        end
        super
      end
    end
  end
end
