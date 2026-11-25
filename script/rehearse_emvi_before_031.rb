# frozen_string_literal: true

require "json"
require "digest"
require_relative "../lib/emvi/maintenance/taxonomy_planning"
require_relative "../lib/emvi/maintenance/atomic_taxonomy_import"
require_relative "support/emvi_production_plan_fixture"

config = ActiveRecord::Base.connection_db_config.configuration_hash
abort "Synthetic 0.30 rehearsal only" unless Rails.env.test? && Decidim.version.to_s == "0.30.9" && config[:database] == "emvi_030_plan_rehearsal" && config[:host] == "/private/tmp/emvi031-pg/socket"
Rails.application.load_tasks
Emvi::Maintenance::AtomicTaxonomyImport.enable!
ActiveJob::Base.queue_adapter = :test
fixture = Object.new.extend(EmviProductionPlanFixture).seed_french_fixture
organization = fixture.instance_variable_get(:@org)
existing = fixture.table("decidim_users").create!(type: "Decidim::User", decidim_organization_id: organization.id, name: "Existing synthetic account", nickname: "existing", email: "existing@example.org", confirmed_at: Time.current)
creator = fixture.table("decidim_users").create!(type: "Decidim::User", decidim_organization_id: organization.id, name: "Synthetic creator", nickname: "creator", email: "creator@example.org", confirmed_at: Time.current)
group = fixture.table("decidim_users").create!(type: "Decidim::UserGroup", decidim_organization_id: organization.id, name: "Unused synthetic group", nickname: "unusedgroup", email: existing.email, confirmed_at: Time.current)
fixture.table("decidim_user_group_memberships").create!(decidim_user_id: creator.id, decidim_user_group_id: group.id, role: "creator")

reports = []
Decidim::Organization.order(:id).each do |org|
  models = %w[ParticipatoryProcessType AssemblyType Scope Area Category].map { |name| "Decidim::Maintenance::ImportModels::#{name}".constantize }
  plan, repairs = Emvi::Maintenance::TaxonomyPlanning.build(org, models)
  ActiveRecord::Base.transaction do
    Decidim::Maintenance::TaxonomyPlan.new(org, models).import(plan) do |importer, section|
      importer.import!
      result = importer.result
      abort "Synthetic import failed" unless result.values_at(:failed_resources, :failed_components).all?(&:empty?)
      result[:taxonomy_map].each do |taxonomy_id, gid|
        next unless GlobalID.parse(gid).model_name.end_with?("::Category")
        Decidim::Metric.where(decidim_organization_id: org.id, decidim_category_id: GlobalID.parse(gid).model_id).update_all(decidim_taxonomy_id: taxonomy_id)
      end
      reports << { organization_id: org.id, section: section, result: result }
    end
  end
end

def digest(value)
  Digest::SHA256.hexdigest(JSON.generate(value))
end

c = ActiveRecord::Base.connection
snapshot = {
  taxonomies: digest(Decidim::Taxonomy.order(:id).pluck(:id, :name, :parent_id, :decidim_organization_id)),
  taxonomizations: digest(Decidim::Taxonomization.order(:id).pluck(:id, :taxonomy_id, :taxonomizable_type, :taxonomizable_id)),
  component_filters: Decidim::Component.order(:id).filter_map { |component| [component.id, Array(component.settings.taxonomy_filters)] if component.settings.respond_to?(:taxonomy_filters) }.to_h,
  answers: digest(c.select_all("SELECT id, body, decidim_user_id, decidim_question_id, decidim_questionnaire_id, session_token, ip_hash FROM decidim_forms_answers ORDER BY id").to_a),
  answer_count: Decidim::Forms::Answer.count,
  registrations: Decidim::Meetings::Registration.count,
  memberships: digest(c.select_all("SELECT * FROM decidim_user_group_memberships ORDER BY id").to_a),
  normal_users: Decidim::User.order(:id).to_h { |user| [user.id, digest(user.attributes.slice("id", "name", "nickname", "email", "encrypted_password", "confirmed_at", "decidim_organization_id"))] },
  group_ids: Decidim::UserGroup.order(:id).pluck(:id),
  unused_group_id: group.id, unused_group_previous_email: existing.email,
  no_hero_organization_id: organization.id,
  published_blocks: Decidim::ContentBlock.where(organization: organization).where.not(published_at: nil).order(:id).pluck(:id, :manifest_name, :weight, :published_at),
  groups_passwords_empty: Decidim::UserGroup.where.not(encrypted_password: "").count.zero?,
  report_sections: reports.length
}
abort "Expected no mail/jobs in the preparation" unless ActionMailer::Base.deliveries.empty? && ActiveJob::Base.queue_adapter.enqueued_jobs.empty?
directory = Pathname.new(ENV.fetch("EMVI_REHEARSAL_EVIDENCE"))
abort "Owned temporary evidence directory only" unless directory.to_s.start_with?("/private/tmp/emvi031-production-rehearsal-")
directory.mkpath
directory.chmod(0o700)
directory.join("before.json").write(JSON.pretty_generate(snapshot))
directory.join("import-sections.json").write(JSON.pretty_generate(reports))
directory.children.each { |path| path.chmod(0o600) }
puts JSON.generate(phase: "0.30 imported", organizations: Decidim::Organization.count, taxonomy_count: Decidim::Taxonomy.count, sections_preserved: reports.length, answers: snapshot[:answer_count], groups: snapshot[:group_ids].length, mail_jobs: 0)
