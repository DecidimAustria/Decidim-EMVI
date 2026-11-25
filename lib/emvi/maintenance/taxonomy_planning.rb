# frozen_string_literal: true

module Emvi
  module Maintenance
    # Planning only: fill absent default-language labels in returned Hash copies.
    # Nothing is assigned to an ActiveRecord attribute or saved to the database.
    # A thread-scoped context keeps normal application behavior unchanged.
    module TaxonomyPlanning
      CONTEXT_KEY = :emvi_taxonomy_planning
      class MissingLabel < StandardError; end
      class InvalidFilterPath < StandardError; end

      def self.build(organization, models)
        with_fallbacks(organization) do
          plan = JSON.parse(Decidim::Maintenance::TaxonomyPlan.new(organization, models).to_json)
          repair_area_filter_paths!(plan, organization)
          isolate_conflicting_filters!(plan)
          plan
        end
      end

      def self.isolate_conflicting_filters!(plan)
        definitions = Hash.new { |hash, key| hash[key] = [] }
        plan.fetch("imported_taxonomies").each do |source, roots|
          next if roots.empty?

          roots.each do |root, data|
            data.fetch("filters").each_with_index do |filter, index|
              identity = [root, filter["internal_name"] || filter["name"], Array(filter["participatory_space_manifests"]).sort]
              definitions[identity] << [source, index, filter]
            end
          end
        end
        definitions.each_value do |entries|
          next unless entries.map { |_, _, filter| filter.fetch("items").sort_by(&:to_s) }.uniq.length > 1

          entries.each do |source, index, filter|
            suffix = filter.fetch("components").sort.map { |gid| GlobalID.parse(gid).model_id }.join("-")
            suffix = "spaces" if suffix.empty?
            # Internal names identify distinct source filters in the admin.
            # Preserve the existing public label instead of exposing these IDs.
            filter["public_name"] ||= filter.fetch("name")
            filter["internal_name"] = "#{filter['internal_name'] || filter.fetch('name')} [#{source}:#{suffix}]"
            Thread.current.fetch(CONTEXT_KEY).fetch(:repairs)[[:filter_identity, source, index]] = {
              model: source, field: :filter_identity, from: "shared", to: "isolated"
            }
          end
        end
      end

      def self.repair_area_filter_paths!(plan, organization)
        locale = organization.default_locale.to_s
        areas = plan.fetch("imported_taxonomies").fetch("decidim_areas")
        return if areas.empty?

        areas.each_value do |root|
          paths = []
          alternatives = Hash.new { |hash, key| hash[key] = [] }
          root.fetch("taxonomies").each do |name, item|
            paths << [name]
            next unless GlobalID.parse(item.fetch("origin")).model_name.end_with?("::AreaType")

            type = GlobalID::Locator.locate(item.fetch("origin"))
            raise InvalidFilterPath unless type && type[:decidim_organization_id] == organization.id

            item.fetch("children").each_key do |child|
              expected = [name, child]
              paths << expected
              alternatives[[type.name[locale], child]] << expected
            end
          end
          root.fetch("filters").each_with_index do |filter, index|
            filter["items"] = filter.fetch("items").map do |path|
              next path if paths.include?(path)

              candidates = alternatives.fetch(path, []).uniq
              raise InvalidFilterPath unless candidates.length == 1

              Thread.current.fetch(CONTEXT_KEY).fetch(:repairs)[[:area_filter, index, path]] = {
                model: "Decidim::Maintenance::ImportModels::Area", field: :filter_path, from: "singular", to: "plural"
              }
              candidates.first
            end
          end
        end
      end

      def self.install!
        return if @installed

        require "decidim/maintenance"
        %w[Scope Area AreaType Category ParticipatoryProcessType AssemblyType].each do |name|
          decorate("Decidim::Maintenance::ImportModels::#{name}".constantize, %i[name plural])
        end
        %w[Decidim::Assembly Decidim::ParticipatoryProcess Decidim::Conference Decidim::Initiative].each do |name|
          klass = name.safe_constantize
          decorate(klass, [:title]) if klass
        end
        decorate(Decidim::Component, [:name])
        @installed = true
      end

      def self.decorate(klass, fields)
        available = fields.select { |field| klass.column_names.include?(field.to_s) }
        wrapper = Module.new
        available.each do |field|
          wrapper.define_method(field) do
            value = super()
            context = Thread.current[Emvi::Maintenance::TaxonomyPlanning::CONTEXT_KEY]
            next value unless context && value.is_a?(Hash)

            target = context.fetch(:target)
            next value if value[target].is_a?(String) && value[target].present?

            source = context.fetch(:locales).find { |locale| value[locale].is_a?(String) && value[locale].present? }
            source ||= value.keys.sort.find { |locale| value[locale].is_a?(String) && value[locale].present? }
            raise Emvi::Maintenance::TaxonomyPlanning::MissingLabel unless source

            context.fetch(:repairs)[[self.class.name, id, field, target]] = { model: self.class.name, field: field, from: source, to: target }
            value.merge(target => value.fetch(source))
          end
        end
        klass.prepend(wrapper)
      end

      def self.with_fallbacks(organization)
        previous = Thread.current[CONTEXT_KEY]
        install!
        target = organization.default_locale.to_s
        context = {
          target: target,
          locales: ([target] + I18n.fallbacks[target].map(&:to_s) + ["en"] + organization.available_locales.map(&:to_s)).uniq,
          repairs: {}
        }
        Thread.current[CONTEXT_KEY] = context
        value = yield
        [value, context.fetch(:repairs).values]
      ensure
        Thread.current[CONTEXT_KEY] = previous
      end
    end
  end
end
