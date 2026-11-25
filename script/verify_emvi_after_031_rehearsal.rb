# frozen_string_literal: true

require "json"
require "digest"
config = ActiveRecord::Base.connection_db_config.configuration_hash
abort "Synthetic 0.31 rehearsal only" unless Rails.env.test? && Decidim.version.to_s == "0.31.9" && config[:database] == "emvi_030_plan_rehearsal" && config[:host] == "/private/tmp/emvi031-pg/socket"
directory = Pathname.new(ENV.fetch("EMVI_REHEARSAL_EVIDENCE"))
abort "Owned temporary evidence directory only" unless directory.to_s.start_with?("/private/tmp/emvi031-production-rehearsal-")
before = JSON.parse(directory.join("before.json").read)
def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))
c = ActiveRecord::Base.connection
checks = {
  taxonomy_identity_names: before.fetch("taxonomies") == digest(Decidim::Taxonomy.order(:id).pluck(:id, :name, :parent_id, :decidim_organization_id)),
  taxonomy_assignments: before.fetch("taxonomizations") == digest(Decidim::Taxonomization.order(:id).pluck(:id, :taxonomy_id, :taxonomizable_type, :taxonomizable_id)),
  component_filters: before.fetch("component_filters") == before.fetch("component_filters").to_h { |id, _| [id, Array(Decidim::Component.find(id).settings.taxonomy_filters)] },
  answer_identity_content: before.fetch("answers") == digest(c.select_all("SELECT id, body, decidim_user_id, decidim_question_id, decidim_questionnaire_id, session_token, ip_hash FROM decidim_forms_responses ORDER BY id").to_a),
  answer_count: before.fetch("answer_count") == Decidim::Forms::Response.count,
  registrations: before.fetch("registrations") == Decidim::Meetings::Registration.count,
  memberships: before.fetch("memberships") == digest(c.select_all("SELECT * FROM decidim_user_group_memberships ORDER BY id").to_a)
}
before.fetch("normal_users").each do |id, expected|
  user = Decidim::User.find(id)
  checks["normal_user_#{id}"] = expected == digest(user.attributes.slice("id", "name", "nickname", "email", "encrypted_password", "confirmed_at", "decidim_organization_id"))
end
hero = Decidim::ContentBlock.find_by!(decidim_organization_id: before.fetch("no_hero_organization_id"), scope_name: "homepage", manifest_name: "hero")
checks[:missing_hero_preserves_cta] = hero[:settings]["cta_button_text_en"] == "Synthetic CTA" && hero[:settings]["cta_button_path_en"] == "/processes"
checks[:new_hero_stays_unpublished] = hero.published_at.nil?
published = Decidim::ContentBlock.where(decidim_organization_id: before.fetch("no_hero_organization_id")).where.not(published_at: nil).order(:id).pluck(:id, :manifest_name, :weight, :published_at)
checks[:visible_homepage_unchanged] = JSON.parse(JSON.generate(published)) == before.fetch("published_blocks")
require "capybara"
manifest = Rails.root.join("public/decidim-packs/manifest.json")
Shakapacker.config.define_singleton_method(:compile?) { false }
Shakapacker.config.define_singleton_method(:manifest_path) { manifest }
session = ActionDispatch::Integration::Session.new(Rails.application)
session.host!(hero.organization.host)
session.get("/", params: { locale: "en" })
checks[:custom_homepage_renders] = session.response.status == 200
checks[:unpublished_hero_not_rendered] = !session.response.body.include?("id=\"hero-#{hero.id}\"")
published_hero = Decidim::ContentBlock.where(manifest_name: "hero").where.not(published_at: nil).first!
session.host!(published_hero.organization.host)
session.get("/", params: { locale: "de" })
checks[:published_hero_still_renders] = session.response.status == 200 && session.response.body.include?("id=\"hero-#{published_hero.id}\"")
group = Decidim::User.find(before.fetch("unused_group_id"))
checks[:unused_group_id_retained] = group.extended_data["group"] == true
checks[:collision_preserved] = group.extended_data["previous_email"] == before.fetch("unused_group_previous_email") && group.extended_data["patched"] == true
checks[:no_group_access_created] = group.email.end_with?(".invalid") && group.encrypted_password.blank?
checks[:all_groups_converted] = Decidim::User.user_group.order(:id).pluck(:id) == before.fetch("group_ids")
checks[:no_pending_schema] = !ActiveRecord::Base.connection_pool.migration_context.needs_migration?
checks[:all_data_up] = DataMigrate::DataMigrator.migrations_status.all? { |state, *_| state == "up" }
directory.join("after.json").write(JSON.pretty_generate(checks))
directory.join("after.json").chmod(0o600)
puts JSON.pretty_generate(checks)
abort "Synthetic end-to-end upgrade check failed" unless checks.values.all?
