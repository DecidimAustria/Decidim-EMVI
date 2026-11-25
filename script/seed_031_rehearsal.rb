# frozen_string_literal: true

# Load a synthetic pre-upgrade fixture into this EMPTY local database only.
require "active_record"
require "open3"
require "bcrypt"
ActiveRecord::Base.establish_connection(adapter: "postgresql", host: "/private/tmp/emvi031-pg/socket", port: 55441, username: "decidim_upgrade", database: ENV["REHEARSAL_EMPTY"] == "1" ? "emvi_031_empty_rehearsal" : "emvi_031_data_rehearsal")
c = ActiveRecord::Base.connection
abort "Rehearsal database must be empty" unless c.tables.empty?
baseline = "9e35d853ee52d07727842fb6e1d8d51a05046176"
schema, status = Open3.capture2("git", "show", "#{baseline}:db/schema.rb")
abort "Cannot read baseline schema" unless status.success?
seen = {}
schema = schema.lines.reject do |line|
  next false unless line.strip.start_with?("add_foreign_key ")
  duplicate = seen[line]
  seen[line] = true
  duplicate
end.join
ActiveRecord::Schema.verbose = false
eval(schema, TOPLEVEL_BINDING, "#{baseline}:db/schema.rb")
c.create_table(:schema_migrations, id: false) { |t| t.string :version, null: false } unless c.table_exists?(:schema_migrations)
Open3.capture2("git", "ls-tree", "-r", "--name-only", baseline, "db/migrate").first.lines.each do |file|
  c.execute("INSERT INTO schema_migrations (version) VALUES (#{c.quote(File.basename(file.strip).split("_").first)}) ON CONFLICT DO NOTHING")
end
exit if ENV["REHEARSAL_EMPTY"] == "1"
models = %w(organizations participatory_processes components users scopes area_types areas categories categorizations coauthorships proposals_proposals meetings_meetings metrics user_group_memberships).to_h do |name|
  [name, Class.new(ActiveRecord::Base) { self.table_name = "decidim_#{name}"; self.inheritance_column = :_type_disabled }]
end
2.times do |i|
  org = models.fetch("organizations").create!(name: { de: "EMVI Probe #{i}", pl: "Proba #{i}" }, host: "emvi-upgrade-#{i}.example.org", default_locale: "de", available_locales: %w(de en pl), reference_prefix: "EMVI#{i}", tos_version: Time.now)
  Class.new(ActiveRecord::Base) { self.table_name = "decidim_content_blocks" }.create!(manifest_name: "hero", scope_name: "homepage", decidim_organization_id: org.id, settings: { existing_setting: i.zero? ? "preserve-me" : "second-hero" }, published_at: Time.now)
  region = models.fetch("scopes").create!(decidim_organization_id: org.id, name: { de: "Region", pl: "Region" }, code: "region")
  district = models.fetch("scopes").create!(decidim_organization_id: org.id, parent_id: region.id, part_of: [region.id], name: { de: "Bezirk", pl: "Dzielnica" }, code: "district")
  neighborhood = models.fetch("scopes").create!(decidim_organization_id: org.id, parent_id: district.id, part_of: [region.id, district.id], name: { de: "Viertel", pl: "Osiedle" }, code: "neighborhood")
  type = models.fetch("area_types").create!(decidim_organization_id: org.id, name: { de: "Gebiet", pl: "Obszar" }, plural: { de: "Gebiete", pl: "Obszary" })
  area = models.fetch("areas").create!(decidim_organization_id: org.id, area_type_id: type.id, name: { de: "Nord", pl: "Polnoc" })
  process = models.fetch("participatory_processes").create!(slug: "probe", title: { de: "EMVI Probe", pl: "Proba" }, subtitle: { de: "Untertitel" }, short_description: { de: "Kurz" }, description: { de: "<p>Inhalt</p>" }, decidim_organization_id: org.id, decidim_scope_id: district.id, decidim_area_id: area.id, published_at: Time.now)
  component = models.fetch("components").create!(manifest_name: "proposals", name: { de: "Ideen", pl: "Pomysly" }, participatory_space_id: process.id, participatory_space_type: "Decidim::ParticipatoryProcess", published_at: Time.now, settings: { global: { scopes_enabled: true, scope_id: district.id } })
  root = models.fetch("categories").create!(name: { de: "Verkehr", pl: "Transport" }, decidim_participatory_space_id: process.id, decidim_participatory_space_type: "Decidim::ParticipatoryProcess")
  child = models.fetch("categories").create!(name: { de: "Radwege", pl: "Rowery" }, parent_id: root.id, decidim_participatory_space_id: process.id, decidim_participatory_space_type: "Decidim::ParticipatoryProcess")
  leaf = models.fetch("categories").create!(name: { de: "Sicherheit", pl: "Bezpieczenstwo" }, parent_id: child.id, decidim_participatory_space_id: process.id, decidim_participatory_space_type: "Decidim::ParticipatoryProcess")
  user = models.fetch("users").create!(type: "Decidim::User", name: "Probe", nickname: "probeuser", email: "probe#{i}@example.org", encrypted_password: BCrypt::Password.create("SyntheticPassword123!"), decidim_organization_id: org.id, confirmed_at: Time.now, accepted_tos_version: Time.now, locale: "de")
  group = models.fetch("users").create!(type: "Decidim::UserGroup", name: "Probegruppe", nickname: "probegruppe", email: i.zero? ? "group#{i}@example.org" : user.email, decidim_organization_id: org.id, extended_data: { verified_at: Time.now })
  models.fetch("user_group_memberships").create!(decidim_user_id: user.id, decidim_user_group_id: group.id, role: "creator")
  proposal = models.fetch("proposals_proposals").create!(decidim_component_id: component.id, decidim_scope_id: neighborhood.id, title: { de: "Sicherer Radweg", pl: "Droga" }, body: { de: "<p>Beschreibung</p>" }, published_at: Time.now)
  models.fetch("coauthorships").create!(decidim_author_id: user.id, decidim_author_type: "Decidim::User", decidim_user_group_id: group.id, coauthorable_type: "Decidim::Proposals::Proposal", coauthorable_id: proposal.id)
  Class.new(ActiveRecord::Base) { self.table_name = "decidim_comments_comments" }.create!(decidim_commentable_type: "Decidim::Proposals::Proposal", decidim_commentable_id: proposal.id, decidim_root_commentable_type: "Decidim::Proposals::Proposal", decidim_root_commentable_id: proposal.id, decidim_author_type: "Decidim::User", decidim_author_id: user.id, decidim_user_group_id: group.id, body: { de: "Gruppe gid://decidim/Decidim::UserGroup/#{group.id}", machine_translations: { en: "Group gid://decidim/Decidim::UserGroup/#{group.id}" } })
  models.fetch("categorizations").create!(decidim_category_id: leaf.id, categorizable_type: "Decidim::Proposals::Proposal", categorizable_id: proposal.id)
  models.fetch("metrics").create!(day: Date.today - 1, metric_type: "proposals", cumulative: 1, quantity: 1, decidim_organization_id: org.id, participatory_space_type: "Decidim::ParticipatoryProcess", participatory_space_id: process.id, decidim_category_id: leaf.id)
end
puts "Seeded two isolated organizations with nested categories/scopes, typed areas, proposal assignments, metrics and group authorship"

def table(name)
  Class.new(ActiveRecord::Base) { self.table_name = name; self.inheritance_column = :_type_disabled }
end
org = models.fetch("organizations").first
process = models.fetch("participatory_processes").first
user = models.fetch("users").find_by!(type: "Decidim::User", decidim_organization_id: org.id)
component_attributes = { name: { de: "Probe" }, participatory_space_id: process.id, participatory_space_type: "Decidim::ParticipatoryProcess", published_at: Time.now }
survey_component = models.fetch("components").create!(**component_attributes, manifest_name: "surveys")
survey = table("decidim_surveys_surveys").create!(decidim_component_id: survey_component.id, published_at: Time.now, allow_answers: true, allow_editing_answers: true)
questionnaire = table("decidim_forms_questionnaires").create!(title: { de: "Fragebogen" }, description: { de: "<p>Probe</p>" }, tos: { de: "Zustimmung" }, questionnaire_for_type: "Decidim::Surveys::Survey", questionnaire_for_id: survey.id, published_at: Time.now)
question = table("decidim_forms_questions").create!(decidim_questionnaire_id: questionnaire.id, position: 0, question_type: "single_option", body: { de: "Frage" })
option = table("decidim_forms_answer_options").create!(decidim_question_id: question.id, body: { de: "Option" }, free_text: false)
643.times do |i|
  answer = table("decidim_forms_answers").create!(body: "Antwort #{i}", decidim_user_id: user.id, decidim_questionnaire_id: questionnaire.id, decidim_question_id: question.id, session_token: "synthetic-#{i}", ip_hash: "synthetic-hash-#{i}")
  table("decidim_forms_answer_choices").create!(decidim_answer_id: answer.id, decidim_answer_option_id: option.id, position: 0, body: { de: "Option" })
end
meeting_component = models.fetch("components").create!(**component_attributes, manifest_name: "meetings")
meeting = table("decidim_meetings_meetings").create!(title: { de: "Treffen" }, description: { de: "<p>Treffen</p>" }, decidim_component_id: meeting_component.id, decidim_author_type: "Decidim::User", decidim_author_id: user.id, start_time: Time.now + 86_400, end_time: Time.now + 90_000, published_at: Time.now, registrations_enabled: true)
table("decidim_meetings_registrations").create!(decidim_user_id: user.id, decidim_meeting_id: meeting.id, code: "REHEARSAL", public_participation: true)
# These historical polymorphic references are repaired by data:migrate.
table("versions").create!(item_type: "Decidim::Forms::Answer", item_id: 1, event: "update", object_changes: { body: ["before", "after"] })
table("decidim_attachments").create!(title: { de: "Synthetischer Anhang" }, attached_to_type: "Decidim::Forms::Answer", attached_to_id: 1, content_type: "text/plain", file_size: "0")

org.update!(header_snippets: '<script>window.upgradeProbe = true;</script>', cta_button_text: { de: "Mitmachen", en: "Participate" }, cta_button_path: "/processes")
table("decidim_content_blocks").create!(manifest_name: "highlighted_content_banner", scope_name: "homepage", decidim_organization_id: org.id, settings: {})
process_group = table("decidim_participatory_process_groups").create!(id: 2, title: { de: "Upgradegruppe" }, description: { de: "Gruppe" }, decidim_organization_id: org.id)
table("decidim_content_blocks").create!(id: 18, manifest_name: "html_1", scope_name: "participatory_process_group_homepage", scoped_resource_id: process_group.id, decidim_organization_id: org.id, settings: { html_content: { de: "<p>Erhaltener Inhalt</p>" } }, published_at: Time.now, weight: 2)
template = table("decidim_templates_templates").create!(name: { de: "Fragebogenvorlage", pl: "Szablon" }, decidim_organization_id: org.id, target: "questionnaires")
template_questionnaire = table("decidim_forms_questionnaires").create!(title: { de: "Vorlagenfragebogen" }, description: { de: "Vorlage" }, tos: { de: "Zustimmung" }, questionnaire_for_type: "Decidim::Templates::Template", questionnaire_for_id: template.id)
template.update!(templatable_type: "Decidim::Forms::Questionnaire", templatable_id: template_questionnaire.id)
template_question = table("decidim_forms_questions").create!(decidim_questionnaire_id: template_questionnaire.id, position: 0, question_type: "single_option", body: { de: "Vorlagenfrage" })
table("decidim_forms_answer_options").create!(decidim_question_id: template_question.id, body: { de: "Vorlagenoption" }, free_text: false)
puts "Seeded two synthetic 0.30 tenants, nested classifications, two groups, comments, 643 answers/choices, one registration and a questionnaire template"
