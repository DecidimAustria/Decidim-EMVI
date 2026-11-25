# frozen_string_literal: true

# Execute with the isolated 0.30 application, not a customer database.
require "minitest/autorun"
require "json"
require_relative "../lib/emvi/maintenance/taxonomy_planning"
require_relative "../lib/emvi/maintenance/atomic_taxonomy_import"
require_relative "support/emvi_production_plan_fixture"

config = ActiveRecord::Base.connection_db_config.configuration_hash
abort "Synthetic 0.30 database only" unless Rails.env.test? && Decidim.version.to_s == "0.30.9" && config[:database] == "emvi_030_plan_rehearsal" && config[:host] == "/private/tmp/emvi031-pg/socket"
Rails.application.load_tasks
Emvi::Maintenance::AtomicTaxonomyImport.enable!

class EmviProductionPlansTest < Minitest::Test
  include EmviProductionPlanFixture

  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    ActiveJob::Base.queue_adapter = :test
    ActionMailer::Base.deliveries.clear
    seed_french_fixture
  end

  def teardown
    assert_nil Thread.current[Emvi::Maintenance::TaxonomyPlanning::CONTEXT_KEY]
    assert_empty ActionMailer::Base.deliveries
    assert_empty ActiveJob::Base.queue_adapter.enqueued_jobs
    ActiveRecord::Base.connection.rollback_transaction
  end

  def origins(plan)
    collect = lambda do |items|
      items.values.flat_map { |item| [item.fetch("origin")] + collect.call(item.fetch("children")) }
    end
    plan.fetch("imported_taxonomies").values.flat_map do |model|
      model.is_a?(Hash) ? model.values.flat_map { |root| collect.call(root.fetch("taxonomies")) } : []
    end
  end

  def build
    Emvi::Maintenance::TaxonomyPlanning.build(@org, @models)
  end

  def test_native_export_omits_sixteen_entries_but_proposed_plan_preserves_all_origins
    native = JSON.parse(Decidim::Maintenance::TaxonomyPlan.new(@org, @models).to_json)
    repaired, repairs = build
    model_names = %w[Scope Area Category]
    count = ->(plan) { origins(plan).count { |gid| model_names.any? { |name| GlobalID.parse(gid).model_name.end_with?("::#{name}") } } }
    assert_equal 3, count.call(native)
    assert_equal 19, count.call(repaired)
    assert_equal 16, count.call(repaired) - count.call(native)
    assert repairs.any? { |row| row[:from] == "en" && row[:to] == "fr" }
    assert_equal 11, repairs.count { |row| row[:field] == :filter_path }
    assert_equal repaired, build.first
    assert_equal({ "en" => "North" }, @scopes.first.reload.name)
    assert_equal({ "en" => "Area 0" }, @areas.first.reload.name)
    assert_equal({ "en" => "Category 0" }, @categories.first.reload.name)
    assert_equal 0, @org.taxonomies.count
    assert_equal native, JSON.parse(Decidim::Maintenance::TaxonomyPlan.new(@org, @models).to_json)
  end

  def test_import_keeps_resource_filter_and_metric_assignments_and_is_repeatable
    plan, = build
    results = []
    2.times do |round|
      Decidim::Maintenance::TaxonomyPlan.new(@org, @models).import(plan) do |importer, section|
        importer.import!
        result = importer.result
        assert_empty result[:failed_resources], section
        assert_empty result[:failed_components], section
        result[:taxonomy_map].each do |taxonomy_id, gid|
          next unless GlobalID.parse(gid).model_name.end_with?("::Category")
          Decidim::Metric.where(decidim_organization_id: @org.id, decidim_category_id: GlobalID.parse(gid).model_id).update_all(decidim_taxonomy_id: taxonomy_id)
        end
        results << [section, result]
      end
      counts = [@org.taxonomies.count, Decidim::TaxonomyFilter.where(root_taxonomy: @org.taxonomies).count, Decidim::Taxonomization.where(taxonomy: @org.taxonomies).count]
      @first_counts ||= counts
      assert_equal @first_counts, counts, "repeat import #{round}"
    end
    assert_equal 10, results.length # preserve all five sections on each run
    assert_equal 0, Decidim::Taxonomy.where.not(decidim_organization_id: @org.id).count
    @proposals.each_with_index do |proposal, i|
      model = Decidim::Proposals::Proposal.find(proposal.id)
      assert_includes model.taxonomies.map { |t| t.name.fetch("fr") }, "Category #{i}"
      assert_includes model.taxonomies.map { |t| t.name.fetch("fr") }, "North"
      assert_equal [@org.id], model.taxonomies.pluck(:decidim_organization_id).uniq
    end
    process = Decidim::ParticipatoryProcess.find(@process.id)
    assert_includes process.taxonomies.map { |t| t.name.fetch("fr") }, "Area 0"
    assert_equal "Category 0", Decidim::Metric.find(@metric.id).taxonomy.name.fetch("fr")
    filter_ids = Array(Decidim::Component.find(@component.id).settings.taxonomy_filters)
    assert_equal 2, filter_ids.length
    assert_equal 2, filter_ids.uniq.length
    area_root = @org.taxonomies.roots.find { |root| root.children.exists?(["name->>'fr' = ?", "Districts"]) }
    area_filter = area_root.taxonomy_filters.first
    assert_equal 11, area_filter.filter_items.count
    assert_equal ["Districts"], area_filter.filter_items.map { |item| item.taxonomy_item.parent.name.fetch("fr") }.uniq
    refute area_root.children.exists?(["name->>'fr' = ?", "District"])
  end

  def test_fallback_context_is_restored_after_failure
    assert_raises(RuntimeError) do
      Emvi::Maintenance::TaxonomyPlanning.with_fallbacks(@org) do
        assert_equal "North", Decidim::Maintenance::ImportModels::Scope.find(@scopes.first.id).name.fetch("fr")
        raise "synthetic failure"
      end
    end
    assert_nil Decidim::Maintenance::ImportModels::Scope.find(@scopes.first.id).name["fr"]
  end

  def test_same_named_component_filters_keep_different_scope_restrictions
    second_process = @process.dup
    second_process.assign_attributes(slug: "plan-second", title: { en: "Second process" }, decidim_scope_id: @scopes.last.id)
    second_process.save!
    second_component = @component.dup
    second_component.assign_attributes(participatory_space_id: second_process.id, settings: { global: { scopes_enabled: true, scope_id: @scopes.last.id } })
    second_component.save!
    plan, repairs = build
    assert repairs.any? { |row| row[:field] == :filter_identity }
    Decidim::Maintenance::TaxonomyPlan.new(@org, @models).import(plan) do |importer, _|
      importer.import!
      assert_empty importer.result[:failed_components]
    end
    scope_filter_for = lambda do |component|
      ids = Decidim::Component.find(component.id).settings.taxonomy_filters
      Decidim::TaxonomyFilter.where(id: ids).find { |filter| filter.root_taxonomy.children.exists?(["name->>'fr' = ?", "North"]) }
    end
    first = scope_filter_for.call(@component)
    second = scope_filter_for.call(second_component)
    refute_equal first.id, second.id
    assert_equal ["North"], first.filter_items.map { |item| item.taxonomy_item.name.fetch("fr") }
    assert_equal ["South"], second.filter_items.map { |item| item.taxonomy_item.name.fetch("fr") }
  end

  def test_shared_german_root_retains_two_independent_space_filters
    @org.update_columns(default_locale: "de", available_locales: %w[de en])
    scope_model = Decidim::Maintenance::ImportModels::Scope
    area_model = Decidim::Maintenance::ImportModels::Area
    plan = nil
    # Mirrors production's enabled-space catalog, where both definitions match.
    original = scope_model.method(:participatory_space_classes)
    catalog = area_model.participatory_space_classes
    begin
      scope_model.define_singleton_method(:participatory_space_classes) { catalog }
      plan, = build
    ensure
      scope_model.define_singleton_method(:participatory_space_classes, original)
    end
    assert_equal plan.fetch("imported_taxonomies").fetch("decidim_scopes").keys, plan.fetch("imported_taxonomies").fetch("decidim_areas").keys
    Decidim::Maintenance::TaxonomyPlan.new(@org, @models).import(plan) do |importer, _|
      importer.import!
      assert_empty importer.result[:failed_components]
    end
    root = @org.taxonomies.roots.find { |item| item.children.exists?(["name->>'de' = ?", "North"]) }
    space_filters = root.taxonomy_filters.reject { |filter| filter.participatory_space_manifests.empty? }
    assert_equal 2, space_filters.length
    assert_equal [2, 11], space_filters.map { |filter| filter.filter_items.count }.sort
    assert_equal 2, space_filters.map { |filter| filter.internal_name.fetch("de") }.uniq.length
    assert_equal 1, space_filters.map { |filter| filter.name.fetch("de") }.uniq.length
  end

  def test_whole_organization_import_can_roll_back_without_partial_changes
    plan, = build
    before = [Decidim::Taxonomy.count, Decidim::Taxonomization.count, Decidim::TaxonomyFilter.count]
    ActiveRecord::Base.transaction(requires_new: true, joinable: true) do
      Decidim::Maintenance::TaxonomyPlan.new(@org, @models).import(plan) do |importer, _|
        importer.import!
        assert_empty importer.result[:failed_resources]
        assert_empty importer.result[:failed_components]
      end
      assert_operator Decidim::Taxonomy.count, :>, before.first
      assert Decidim::Taxonomy.all.all? { |taxonomy| taxonomy.part_of.none?(&:nil?) }
      raise ActiveRecord::Rollback
    end
    assert_equal before, [Decidim::Taxonomy.count, Decidim::Taxonomization.count, Decidim::TaxonomyFilter.count]
    assert_empty Array(Decidim::Component.find(@component.id).settings.taxonomy_filters)
  end
end
