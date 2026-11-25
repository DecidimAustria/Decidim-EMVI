# frozen_string_literal: true

# Run with Rails runner in the CURRENT 0.30.9 production pod. This exports only
# upgrade planning data; it never invokes imports, migrations, jobs or mail.
# Output contains aggregate findings only: no names, contacts, titles or resource IDs.
require "json"
require "digest"
require "decidim/maintenance"

abort "Expected EMVI production 0.30.9" unless Rails.env.production? && Decidim.version.to_s == "0.30.9"
source_revision = Bundler.locked_gems.specs.find { |spec| spec.name == "decidim-core" }.source.revision
abort "Unexpected production framework revision" unless source_revision == "a01873761bc05359ec5937268c0d982e1d3bfdbf"
abort "Explicit planning acknowledgement required" unless ENV["EMVI_READ_ONLY_PLANNING"] == "1"

def resource_organization(record)
  return record[:decidim_organization_id] if record.has_attribute?(:decidim_organization_id)
  return record.organization.id if record.respond_to?(:organization) && record.organization
  return record.participatory_space.organization.id if record.respond_to?(:participatory_space) && record.participatory_space
  return record.component.organization.id if record.respond_to?(:component) && record.component
end

def plan_items(items, path = [], &block)
  items.each do |name, item|
    current = path + [name]
    yield current, item
    plan_items(item.fetch("children"), current, &block)
  end
end

result = nil
begin
  ActiveRecord::Base.transaction(isolation: :repeatable_read) do
    connection = ActiveRecord::Base.connection
    connection.execute("SET TRANSACTION READ ONLY")
    connection.execute("SET LOCAL statement_timeout = '60s'")
    connection.execute("SET LOCAL lock_timeout = '2s'")
    abort "Read-only protection missing" unless connection.select_value("SHOW transaction_read_only") == "on"
    organizations = Decidim::Organization.order(:id).to_a
    abort "Unexpected EMVI production tenants" unless organizations.length == 7 && organizations.any? { |org| org.host == "www.berlinmitallengestalten.de" }
    models = %w[ParticipatoryProcessType AssemblyType Scope Area Category].map { |name| "Decidim::Maintenance::ImportModels::#{name}".constantize }
    all_origins = []
    plans = organizations.map do |organization|
      build_plan = -> { JSON.parse(Decidim::Maintenance::TaxonomyPlan.new(organization, models).to_json) }
      if ENV["EMVI_PLAN_REPAIRS"] == "1"
        abort "Load the reviewed planning library first" unless defined?(Emvi::Maintenance::TaxonomyPlanning)
        plan, label_repairs = Emvi::Maintenance::TaxonomyPlanning.build(organization, models)
      else
        plan = build_plan.call
        label_repairs = []
      end
      references = {}
      resource_origins = Hash.new { |hash, key| hash[key] = [] }
      missing_filter_paths = []
      roots = Hash.new { |hash, key| hash[key] = [] }
      origins = []
      root_paths = Hash.new { |hash, key| hash[key] = Hash.new { |paths, path| paths[path] = [] } }
      filter_definitions = Hash.new { |hash, key| hash[key] = [] }
      plan.fetch("imported_taxonomies").each do |model, taxonomies|
        next if taxonomies.empty?
        taxonomies.each do |root, data|
          roots[root] << model
          paths = []
          plan_items(data.fetch("taxonomies")) do |path, item|
            paths << path
            origins << item.fetch("origin")
            root_paths[root][path] << item.fetch("origin")
            item.fetch("resources").each_key do |gid|
              references[gid] = "resource"
              resource_origins[gid] << item.fetch("origin")
            end
          end
          data.fetch("filters").each do |filter|
            identity = [root, filter["internal_name"] || filter["name"], Array(filter["participatory_space_manifests"]).sort]
            filter_definitions[identity] << filter.fetch("items").sort_by(&:to_s)
            filter.fetch("components").each { |gid| references[gid] = "component" }
            filter.fetch("items").each do |path|
              next if paths.include?(path)
              missing_filter_paths << { model: model, root: root, filter: filter["internal_name"] || filter["name"], path: path }
            end
          end
        end
      end
      all_origins.concat(origins)
      resolved = references.map do |gid, kind|
        record = GlobalID::Locator.locate(gid)
        row = { gid: gid, kind: kind, exists: !record.nil? }
        if record
          row.merge!(organization_id: resource_organization(record), model: record.class.name,
                     supports_taxonomy: record.respond_to?(:taxonomy) || record.respond_to?(:taxonomies),
                     singular_taxonomy: record.respond_to?(:taxonomy))
          row[:existing_filters] = Array(record.settings.taxonomy_filters) if kind == "component"
        end
        row
      end
      {
        organization_id: organization.id,
        plan_repair_counts: label_repairs.group_by { |row| [row[:model], row[:field], row[:from], row[:to]].join("/") }.transform_values(&:length),
        sha256: Digest::SHA256.hexdigest(JSON.generate(plan)),
        root_collisions: roots.values.select { |names| names.length > 1 },
        shared_root_path_collision_count: root_paths.values.sum { |paths| paths.values.count { |gids| gids.uniq.length > 1 } },
        conflicting_filter_definition_count: filter_definitions.values.count { |definitions| definitions.uniq.length > 1 },
        model_node_counts: origins.uniq.group_by { |gid| GlobalID.parse(gid).model_name }.transform_values(&:length),
        missing_filter_path_counts: missing_filter_paths.group_by { |row| row[:model] }.transform_values(&:length),
        singular_resource_conflict_counts: resolved.select { |row| row[:singular_taxonomy] && resource_origins[row[:gid]].uniq.length > 1 }.group_by { |row| row[:model] }.transform_values(&:length),
        reference_counts: resolved.group_by { |row| row[:model] || "missing" }.transform_values(&:length),
        invalid_reference_counts: resolved.select { |row| !row[:exists] || row[:organization_id] != organization.id || (row[:kind] == "resource" && !row[:supports_taxonomy]) }.group_by { |row| row[:model] || "missing" }.transform_values(&:length),
        total_filters: plan.fetch("imported_taxonomies").values.sum { |model| model.is_a?(Hash) ? model.values.sum { |root| root.fetch("filters").length } : 0 },
        components_with_existing_filters: resolved.count { |row| row[:existing_filters]&.any? }
      }
    end
    coverage = %w[Scope Area Category].map do |name|
      model = "Decidim::Maintenance::ImportModels::#{name}".constantize
      rows = model.order(:id).to_a
      missing = rows.reject { |row| all_origins.include?(row.to_global_id.to_s) }
      findings = missing.map do |row|
        organization_id = resource_organization(row)
        organization = organizations.find { |org| org.id == organization_id }
        locale = organization&.default_locale || "en"
        parent_missing = row.has_attribute?(:parent_id) && row[:parent_id] && !model.exists?(row[:parent_id])
        scope = organization_id && row.has_attribute?(:decidim_organization_id) ? model.where(decidim_organization_id: organization_id) : model.all
        scope = scope.where(parent_id: row[:parent_id]) if row.has_attribute?(:parent_id)
        scope = scope.where(decidim_participatory_space_type: row[:decidim_participatory_space_type], decidim_participatory_space_id: row[:decidim_participatory_space_id]) if row.has_attribute?(:decidim_participatory_space_id)
        duplicate_label = scope.where("name->>? = ?", locale, row.name[locale]).count > 1
        { organization_id: organization_id, orphan_space: organization_id.nil?, parent_missing: !!parent_missing,
          blank_default_label: row.name[locale].blank?, duplicate_sibling_label: duplicate_label,
          available_name_locales: row.name.select { |_, value| value.is_a?(String) && value.present? }.keys,
          linked_resources: row.resources.length }
      end
      { model: name, source_count: rows.length, planned_count: rows.length - missing.length,
        missing_by_organization: findings.group_by { |row| row[:organization_id] }.transform_values(&:length),
        missing_with_linked_resources: findings.count { |row| row[:linked_resources].positive? },
        missing_linked_resources_total: findings.sum { |row| row[:linked_resources] },
        orphan_space_count: findings.count { |row| row[:orphan_space] }, parent_missing_count: findings.count { |row| row[:parent_missing] },
        blank_default_label_count: findings.count { |row| row[:blank_default_label] }, duplicate_sibling_label_count: findings.count { |row| row[:duplicate_sibling_label] },
        available_missing_name_locales: findings.flat_map { |row| row[:available_name_locales] }.tally }
    end
    group_rows = Decidim::UserGroup.unscoped.order(:id).map do |group|
      membership_rows = connection.select_all("SELECT id, decidim_user_id, role FROM decidim_user_group_memberships WHERE decidim_user_group_id = #{Integer(group.id)} ORDER BY id").to_a
      members = membership_rows.map do |membership|
        user = Decidim::User.unscoped.find(membership.fetch("decidim_user_id"))
        { role: membership.fetch("role"), confirmed: user.confirmed?, blocked: user.blocked?, deleted: user.deleted?,
          same_email_as_group: user.email == group.email }
      end
      references = connection.tables.filter_map do |table|
        columns = connection.columns(table).map(&:name)
        next unless columns.include?("decidim_user_group_id") && table != "decidim_user_group_memberships"
        selected = %w[id decidim_author_id decidim_author_type].select { |name| columns.include?(name) }
        next if selected.empty?
        rows = connection.select_all("SELECT #{selected.map { |name| connection.quote_column_name(name) }.join(', ')} FROM #{connection.quote_table_name(table)} WHERE decidim_user_group_id = #{Integer(group.id)} ORDER BY id").to_a
        { table: table, count: rows.length } if rows.any?
      end
      {
        id: group.id, organization_id: group.decidim_organization_id, email_blank: group.email.blank?,
        email_collision_count: Decidim::UserBaseEntity.unscoped.where(decidim_organization_id: group.decidim_organization_id, email: group.email).where.not(id: group.id).count,
        confirmed: group.confirmed?, blocked: group.blocked?, deleted: group.deleted?,
        password_present: group.encrypted_password.present?,
        legacy_action_logs: Decidim::ActionLog.where(resource_type: "Decidim::UserGroup", resource_id: group.id).count,
        legacy_follows: Decidim::Follow.where(decidim_followable_type: "Decidim::UserGroup", decidim_followable_id: group.id).count,
        legacy_profile_attachments: ActiveStorage::Attachment.where(record_type: "Decidim::UserGroup", record_id: group.id).count,
        profile_attachments: ActiveStorage::Attachment.where(record_type: ["Decidim::UserGroup", "Decidim::UserBaseEntity"], record_id: group.id).count,
        membership_count: members.length,
        membership_roles: members.group_by { |row| row[:role] }.transform_values(&:length),
        confirmed_member_count: members.count { |row| row[:confirmed] },
        blocked_member_count: members.count { |row| row[:blocked] },
        deleted_member_count: members.count { |row| row[:deleted] },
        members_sharing_group_email: members.count { |row| row[:same_email_as_group] }, references: references
      }
    end
    failures = GoodJob::Job.where.not(error: nil).pluck(:error, :serialized_params).group_by do |error, params|
      [params["job_class"], error.to_s[/\A[A-Za-z_:]+/].to_s.sub(/:\z/, "")]
    end.transform_values(&:length)
    result = {
      failed_job_classes: failures.map { |(job, error), count| { job: job, error: error, count: count } },
      framework_revision: source_revision,
      captured_at: Time.now.utc.iso8601, version: Decidim.version.to_s, ruby: RUBY_VERSION,
      transaction_read_only: true,
      organization_ids: organizations.map(&:id),
      plans: plans, coverage: coverage, groups: group_rows,
      homepage_block_counts: organizations.map { |org| { organization_id: org.id, blocks: Decidim::ContentBlock.where(organization: org, scope_name: "homepage").group(:manifest_name).count } },
      locales: organizations.map { |org| { organization_id: org.id, default_locale: org.default_locale } },
      counts: { users: Decidim::User.count, groups: group_rows.length, categories: connection.select_value("SELECT count(*) FROM decidim_categories"),
                scopes: Decidim::Scope.count, areas: Decidim::Area.count, taxonomies: Decidim::Taxonomy.count,
                answers: Decidim::Forms::Answer.count, registrations: Decidim::Meetings::Registration.count,
                active_jobs: GoodJob::Job.where(finished_at: nil).count, failed_jobs: GoodJob::Job.where.not(error: nil).count }
    }
  end
  puts "EMVI_PRODUCTION_PREFLIGHT=" + JSON.generate(result)
rescue StandardError => error
  warn JSON.generate(error_class: error.class.name, locations: error.backtrace.first(3))
  exit 1
end
