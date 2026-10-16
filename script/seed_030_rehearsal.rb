# frozen_string_literal: true

# Load a synthetic pre-upgrade fixture into this EMPTY local database only.
require "active_record"
require "open3"
require "bcrypt"
ActiveRecord::Base.establish_connection(adapter: "postgresql", host: "/private/tmp/decidim-0297-pg/socket", port: 55439, username: "decidim_upgrade", database: "emvi_030_data_rehearsal")
c = ActiveRecord::Base.connection
abort "Rehearsal database must be empty" unless c.tables.empty?
baseline = "5e7f1d41ccc217a09edb448bae9cfccaf0347909"
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
models = %w(organizations participatory_processes components users scopes area_types areas categories categorizations coauthorships proposals_proposals meetings_meetings metrics user_group_memberships).to_h do |name|
  [name, Class.new(ActiveRecord::Base) { self.table_name = "decidim_#{name}"; self.inheritance_column = :_type_disabled }]
end
2.times do |i|
  org = models.fetch("organizations").create!(name: { de: "EMVI Probe #{i}", pl: "Proba" }, host: "emvi-upgrade-#{i}.example.org", default_locale: "de", available_locales: %w(de en pl), reference_prefix: "EMVI#{i}", tos_version: Time.now)
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
  user = models.fetch("users").create!(type: "Decidim::User", name: "Probe", nickname: "ProbeUser", email: "probe#{i}@example.org", encrypted_password: BCrypt::Password.create("SyntheticPassword123!"), decidim_organization_id: org.id, confirmed_at: Time.now, accepted_tos_version: Time.now, locale: "de")
  group = models.fetch("users").create!(type: "Decidim::UserGroup", name: "Probegruppe", nickname: "probegruppe", email: "group#{i}@example.org", decidim_organization_id: org.id, extended_data: { verified_at: Time.now })
  models.fetch("user_group_memberships").create!(decidim_user_id: user.id, decidim_user_group_id: group.id, role: "manager")
  proposal = models.fetch("proposals_proposals").create!(decidim_component_id: component.id, decidim_scope_id: neighborhood.id, title: { de: "Sicherer Radweg", pl: "Droga" }, body: { de: "<p>Beschreibung</p>" }, published_at: Time.now)
  models.fetch("coauthorships").create!(decidim_author_id: user.id, decidim_author_type: "Decidim::User", decidim_user_group_id: group.id, coauthorable_type: "Decidim::Proposals::Proposal", coauthorable_id: proposal.id)
  models.fetch("categorizations").create!(decidim_category_id: leaf.id, categorizable_type: "Decidim::Proposals::Proposal", categorizable_id: proposal.id)
  models.fetch("metrics").create!(day: Date.today - 1, metric_type: "proposals", cumulative: 1, quantity: 1, decidim_organization_id: org.id, participatory_space_type: "Decidim::ParticipatoryProcess", participatory_space_id: process.id, decidim_category_id: leaf.id)
end
puts "Seeded two isolated organizations with nested categories/scopes, typed areas, proposal assignments, metrics and group authorship"
