# frozen_string_literal: true

# Run only with Rails runner against the isolated, migrated synthetic fixture.
require "minitest/autorun"
require "json"
config = ActiveRecord::Base.connection_db_config.configuration_hash
unless Rails.env.test? && config[:database] == "emvi_030_data_rehearsal" && config[:host] == "/private/tmp/decidim-0297-pg/socket"
  abort "Use only the isolated emvi_030_data_rehearsal database in test mode"
end
Rails.application.load_tasks
manifest = Rails.root.join("public/decidim-packs/manifest.json")
abort "Compile production assets first" unless manifest.exist?
Shakapacker.config.define_singleton_method(:compile?) { false }
Shakapacker.config.define_singleton_method(:manifest_path) { manifest }

class Emvi030UpgradeTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @organizations = Decidim::Organization.order(:id).to_a
    @organization = @organizations.first
    @process = Decidim::ParticipatoryProcess.find_by!(decidim_organization_id: @organization.id)
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    RequestStore.store[:toggle_machine_translations] = nil
  end

  def teardown
    RequestStore.store[:toggle_machine_translations] = nil
    ActiveRecord::Base.connection.rollback_transaction
  end

  def invoke(name, *args)
    task = Rake::Task[name]
    task.reenable
    task.invoke(*args)
  end

  def import_taxonomies
    invoke("decidim:taxonomies:make_plan")
    @organizations.each do |organization|
      plan = Rails.root.join("tmp/taxonomies/#{organization.host}_plan.json")
      data = JSON.parse(plan.read)
      assert data.fetch("imported_taxonomies").values.any?(&:present?), "expected a nonempty import"
      invoke("decidim:taxonomies:import_plan", plan.to_s)
      result = Rails.root.join("tmp/taxonomies/#{organization.host}_result.json")
      data = JSON.parse(result.read)
      assert_empty data.fetch("failed_resources")
      assert_empty data.fetch("failed_components")
      invoke("decidim:taxonomies:update_metrics", result.to_s)
    end
  end

  def test_versions_modules_and_schema
    assert_equal "0.30.9", Decidim.version
    assert_equal "0.13.2", Gem.loaded_specs.fetch("decidim-decidim_awesome").version.to_s
    assert_equal "0.3.2", Gem.loaded_specs.fetch("decidim-amazon_translate").version.to_s
    refute ActiveRecord::Base.connection.migration_context.needs_migration?
  end

  def test_nonempty_taxonomy_import_preserves_assignments_and_organization_boundaries
    import_taxonomies
    @organizations.each do |organization|
      process = Decidim::ParticipatoryProcess.find_by!(decidim_organization_id: organization.id)
      proposal = Decidim::Proposals::Proposal.find_by!(decidim_component_id: process.components.find_by!(manifest_name: "proposals").id)
      assert_includes process.taxonomies.map { |t| t.name["de"] }, "Nord"
      assert_includes process.taxonomies.map { |t| t.name["de"] }, "Bezirk"
      assert_includes proposal.taxonomies.map { |t| t.name["de"] }, "Viertel"
      assert_includes proposal.taxonomies.map { |t| t.name["de"] }, "Radwege > Sicherheit"
      assert_equal [organization.id], proposal.taxonomies.pluck(:decidim_organization_id).uniq
      category = proposal.taxonomies.find { |t| t.name["de"] == "Radwege > Sicherheit" }
      assert_equal "Bezpieczenstwo", category.name["pl"]
      assert_equal category.id, Decidim::Metric.find_by!(decidim_organization_id: organization.id).decidim_taxonomy_id
      filters = process.components.first.settings.taxonomy_filters
      assert_operator filters.length, :>=, 2
    end
    # German translates both scope and area roots as "Bereiche"; review this
    # merged root in real plans, while retaining both filters/assignments.
    assert_equal 4, Decidim::Taxonomy.roots.count
  end

  def test_taxonomy_import_is_idempotent
    import_taxonomies
    before = [Decidim::Taxonomy.count, Decidim::TaxonomyFilter.count, Decidim::Taxonomization.count]
    import_taxonomies
    assert_equal before, [Decidim::Taxonomy.count, Decidim::TaxonomyFilter.count, Decidim::Taxonomization.count]
  end

  def test_group_authorship_survives_schema_upgrade
    assert_equal 2, Decidim::UserGroup.count
    Decidim::Proposals::Proposal.find_each do |proposal|
      author = proposal.coauthorships.first
      assert Decidim::UserGroup.exists?(author.decidim_user_group_id)
      assert_equal proposal.organization.id, author.user_group.decidim_organization_id
    end
  end

  def test_polish_terms_interpolation
    value = I18n.t("decidim.pages.terms_of_service.refuse.modal_body", locale: :pl, download_your_data_path: "/download-data", delete_path: "/delete-account")
    assert_includes value, 'href="/download-data"'
    assert_includes value, 'href="/delete-account"'
    refute_includes value, "%{"
  end

  def test_application_translator_preserves_html_and_persists_translation
    resource = @process
    translator = AwsTranslator.new(resource, :description, resource.description.fetch("de").dup, "pl", "de")
    translator.define_singleton_method(:aws_translate) { Struct.new(:translated_text).new("<p>Przetlumaczone</p>") }
    translator.translate
    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == Decidim::MachineTranslationSaveJob }
    assert_equal 1, jobs.length
    Decidim::MachineTranslationSaveJob.perform_now(*ActiveJob::Arguments.deserialize(jobs.first[:args]))
    assert_equal "<p>Przetlumaczone</p>", resource.reload.description.dig("machine_translations", "pl")
  end

  def test_public_homepage
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.host!(@organization.host)
    session.get("/")
    assert_equal 200, session.response.status
  end

  def test_error_translation_link_without_query
    url = "http://#{@organization.host}/missing"
    controller = Decidim::ApplicationController.new
    controller.set_request!(ActionDispatch::Request.new(Rack::MockRequest.env_for(url)))
    organization = @organization
    controller.define_singleton_method(:current_organization) { organization }
    RequestStore.store[:toggle_machine_translations] = true
    cell = Cell::ViewModel.cell("decidim/translation_bar", @organization, context: { controller: controller })
    cell.define_singleton_method(:button_text) { "Original" }
    assert_equal url, Nokogiri::HTML.fragment(cell.link).at_css("a")["href"]
  end

  def test_nickname_conversion_and_cleanup_keep_group_authorship
    invoke("decidim:upgrade:fix_nickname_casing")
    assert_equal 0, Decidim::User.where("nickname <> lower(nickname)").count
    %w[decidim_proposals:upgrade:set_categories decidim:upgrade:clean:clean_deleted_users decidim:upgrade:clean:invalid_private_exports decidim:upgrade:fix_action_log decidim:upgrade:clean:remove_private_exports_attachments decidim:upgrade:remove_deleted_users_left_data decidim:upgrade:fix_deleted_private_follows decidim:upgrade:attachments_cleanup].each { |name| invoke(name) }
    assert_equal 2, Decidim::User.count
    assert_equal 2, Decidim::UserGroup.count
    assert_equal 2, Decidim::Coauthorship.count
  end
end
