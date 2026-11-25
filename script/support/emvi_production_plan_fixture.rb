# frozen_string_literal: true

# Synthetic fixture shared by the 0.30 tests and the full 0.30 -> 0.31 rehearsal.
module EmviProductionPlanFixture
  def table(name)
    @tables ||= {}
    @tables[name] ||= Class.new(ActiveRecord::Base) { self.table_name = name; self.inheritance_column = :_type_disabled }
  end

  def seed_french_fixture
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    abort "Synthetic planning database only" unless Rails.env.test? && config[:database] == "emvi_030_plan_rehearsal" && config[:host] == "/private/tmp/emvi031-pg/socket"
    @org = table("decidim_organizations").create!(name: { fr: "Préparation synthétique" }, host: "emvi-plan-fr.example.org", default_locale: "fr", available_locales: %w[fr en], reference_prefix: "PLAN", tos_version: Time.current)
    @org = Decidim::Organization.find(@org.id)
    @org.update_columns(cta_button_text: { "en" => "Synthetic CTA" }, cta_button_path: "/processes")
    table("decidim_content_blocks").create!(decidim_organization_id: @org.id, scope_name: "homepage", manifest_name: "html", settings: { "html_content_en" => "Synthetic public content" }, published_at: Time.current, weight: 2)
    @scopes = %w[North South].map { |name| table("decidim_scopes").create!(decidim_organization_id: @org.id, name: { en: name }, code: name.downcase) }
    type = table("decidim_area_types").create!(decidim_organization_id: @org.id, name: { en: "District" }, plural: { en: "Districts" })
    @areas = 11.times.map { |i| table("decidim_areas").create!(decidim_organization_id: @org.id, area_type_id: type.id, name: { en: "Area #{i}" }) }
    @process = table("decidim_participatory_processes").create!(slug: "plan", title: { en: "Plan process" }, subtitle: { en: "Subtitle" }, short_description: { en: "Short" }, description: { en: "<p>Synthetic</p>" }, decidim_organization_id: @org.id, decidim_scope_id: @scopes.first.id, decidim_area_id: @areas.first.id, published_at: Time.current, scopes_enabled: true)
    @component = table("decidim_components").create!(manifest_name: "proposals", name: { en: "Ideas" }, participatory_space_id: @process.id, participatory_space_type: "Decidim::ParticipatoryProcess", published_at: Time.current, settings: { global: { scopes_enabled: true, scope_id: @scopes.first.id } })
    @categories = 6.times.map { |i| table("decidim_categories").create!(name: { en: "Category #{i}" }, decidim_participatory_space_id: @process.id, decidim_participatory_space_type: "Decidim::ParticipatoryProcess") }
    @proposals = @categories.each_with_index.map do |category, i|
      proposal = table("decidim_proposals_proposals").create!(decidim_component_id: @component.id, decidim_scope_id: @scopes.first.id, title: { en: "Proposal #{i}" }, body: { en: "<p>Synthetic</p>" }, published_at: Time.current)
      table("decidim_categorizations").create!(decidim_category_id: category.id, categorizable_type: "Decidim::Proposals::Proposal", categorizable_id: proposal.id)
      proposal
    end
    @metric = table("decidim_metrics").create!(day: Date.current - 1, metric_type: "proposals", cumulative: 1, quantity: 1, decidim_organization_id: @org.id, participatory_space_type: "Decidim::ParticipatoryProcess", participatory_space_id: @process.id, decidim_category_id: @categories.first.id)
    @models = %w[ParticipatoryProcessType AssemblyType Scope Area Category].map { |name| "Decidim::Maintenance::ImportModels::#{name}".constantize }
    self
  end
end
