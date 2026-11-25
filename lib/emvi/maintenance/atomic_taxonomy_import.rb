# frozen_string_literal: true

module Emvi
  module Maintenance
    # The 0.30 importer relies on after_create_commit to populate each taxonomy's
    # ancestry. An outer transaction otherwise leaves nil ancestor IDs until the
    # entire import commits, making the next child fail cycle validation.
    # Complete that same native hook before importing descendants. The normal
    # commit hook remains in place and becomes a no-op once ancestry is correct.
    module AtomicTaxonomyImport
      def self.enable!
        raise "Only reviewed for 0.30.9" unless Decidim.version.to_s == "0.30.9"

        require "decidim/maintenance"
        importer = Decidim::Maintenance::TaxonomyImporter
        importer.prepend(self) unless importer.ancestors.include?(self)
      end

      private

      def create_taxonomy!(association, name)
        taxonomy = super
        taxonomy.send(:create_part_of) if taxonomy.part_of.any?(&:nil?)
        taxonomy
      end
    end
  end
end
