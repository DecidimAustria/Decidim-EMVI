# frozen_string_literal: true

# Rails runner verification, exclusively for the migrated synthetic rehearsal.
require "minitest/autorun"
require "json"
require "capybara" # Decidim test URL resolver; no browser session is started.

connection_config = ActiveRecord::Base.connection_db_config.configuration_hash
unless Rails.env.test? && connection_config[:database] == "emvi_031_data_rehearsal" && connection_config[:host] == "/private/tmp/emvi031-pg/socket"
  abort "Use only the isolated emvi_031_data_rehearsal database in test mode"
end
Rails.application.load_tasks
manifest = Rails.root.join("public/decidim-packs/manifest.json")
abort "Compile production assets first" unless manifest.exist?
Shakapacker.config.define_singleton_method(:compile?) { false }
Shakapacker.config.define_singleton_method(:manifest_path) { manifest }

class Upgrade031Test < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @organization = Decidim::Organization.find_by!(host: "emvi-upgrade-0.example.org")
    @process = Decidim::ParticipatoryProcess.find_by!(slug: "probe", organization: @organization)
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActionMailer::Base.deliveries.clear
    RequestStore.store[:toggle_machine_translations] = nil
  end

  def teardown
    RequestStore.store[:toggle_machine_translations] = nil
    ActiveRecord::Base.connection.rollback_transaction
  end

  def controller_for(url)
    controller = Decidim::ApplicationController.new
    controller.set_request!(ActionDispatch::Request.new(Rack::MockRequest.env_for(url)))
    organization = @organization
    controller.define_singleton_method(:current_organization) { organization }
    controller
  end

  def test_dependencies_and_migrations
    %w(decidim decidim-core decidim-dev decidim-forms decidim-surveys decidim-meetings).each do |name|
      assert_equal "0.31.9", Gem.loaded_specs.fetch(name).version.to_s
    end
    assert_equal "0.14.5", Gem.loaded_specs.fetch("decidim-decidim_awesome").version.to_s
    assert_equal "8.3.0", Gem.loaded_specs.fetch("shakapacker").version.to_s
    assert_includes Decidim.component_manifests.map(&:name), :awesome_map
    refute ActiveRecord::Base.connection_pool.migration_context.needs_migration?
  end

  def test_answers_keep_content_identity_associations_and_choices
    responses = Decidim::Forms::Response.order(:id).to_a
    assert_equal 643, responses.length
    responses.each_with_index do |response, i|
      assert_equal i + 1, response.id
      assert_equal "Antwort #{i}", response.body
      assert_equal "synthetic-#{i}", response.session_token
      assert_equal "synthetic-hash-#{i}", response.ip_hash
      assert_equal @organization, response.user.organization
      assert_equal response.questionnaire, response.question.questionnaire
      assert_equal "surveys", response.questionnaire.questionnaire_for.component.manifest_name
      assert_equal 1, response.choices.count
      assert_equal "Option", response.choices.first.body.fetch("de")
      assert_equal response.question, response.choices.first.response_option.question
    end
    refute ActiveRecord::Base.connection.table_exists?(:decidim_forms_answers)
  end

  def test_data_migrations_repair_historical_polymorphic_references
    assert_equal "Decidim::Forms::Response", PaperTrail::Version.find_by!(event: "update", item_id: 1).item_type
    assert_equal "Decidim::Forms::Response", Decidim::Attachment.find_by!(title: { de: "Synthetischer Anhang" }).attached_to_type
    assert_equal 0, PaperTrail::Version.where(item_type: "Decidim::Forms::Answer").count
    assert_equal 0, Decidim::Attachment.where(attached_to_type: "Decidim::Forms::Answer").count
  end

  def test_registration_and_legacy_group_html_survive
    registration = Decidim::Meetings::Registration.find_by!(code: "REHEARSAL")
    assert_equal "probe0@example.org", registration.user.email
    assert_equal "Treffen", registration.meeting.title.fetch("de")
    assert registration.public_participation
    assert_equal 48, registration.meeting.send_reminders_before_hours
    block = Decidim::ContentBlock.find(18)
    assert_equal "html_1", block.manifest_name
    assert_equal 2, block.scoped_resource_id
    assert_equal 2, block.weight
    assert block.published_at
    html = Cell::ViewModel.cell("decidim/content_blocks/html", block, context: { controller: controller_for("http://emvi-upgrade-0.example.org/") }).call
    assert_includes html, "Erhaltener Inhalt"
  end

  def test_translation_guard_and_amazon_persistence
    controller = controller_for("http://emvi-upgrade-0.example.org/missing")
    RequestStore.store[:toggle_machine_translations] = true
    cell = Cell::ViewModel.cell("decidim/translation_bar", @organization, context: { controller: controller })
    cell.define_singleton_method(:button_text) { "Original" }
    assert_equal "http://emvi-upgrade-0.example.org/missing", Nokogiri::HTML.fragment(cell.link).at_css("a")["href"]
    assert Decidim.enable_machine_translations
    assert_equal "Decidim::AmazonTranslate::AmazonTranslator", Decidim.machine_translation_service
    client = Aws::Translate::Client.new(region: "eu-central-1", stub_responses: true)
    client.stub_responses(:translate_text, translated_text: "Hallo", source_language_code: "en", target_language_code: "de")
    translator = Decidim::AmazonTranslate::AmazonTranslator.new(@process, :description, @process.description.fetch("de").dup, "de", "en")
    translator.define_singleton_method(:aws_client) { client }
    translator.translate
    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == Decidim::MachineTranslationSaveJob }
    assert_equal 1, jobs.length
    Decidim::MachineTranslationSaveJob.perform_now(*ActiveJob::Arguments.deserialize(jobs.first[:args]))
    assert_equal "<p>Hallo</p>", @process.reload.description.dig("machine_translations", "de")
  end

  def test_locale_menu_and_regional_parent_loading
    locales = %w(bs ca cs de en es fr hr it nl pl pt ro ru el sl sr-CS tr-TR ar-SA fa-IR uk zh-TW)
    entries = Object.new.extend(Decidim::LocalizedLocalesHelper).localized_locales(locales)
    assert_equal locales.sort, entries.map { |entry| entry.id.to_s }.sort
    arabic = entries.find { |entry| entry.id.to_s == "ar-SA" }
    assert_includes arabic.name, "العربية"
    refute_includes Decidim.available_locales.map(&:to_s), "ar"
    assert_includes I18n.available_locales.map(&:to_s), "ar"
    locales.each do |locale|
      assert I18n.t("locale.name", locale: locale, raise: true).present?
    end
  end

  def test_public_rendering_saved_snippets_and_api_docs
    previous = Decidim.enable_html_header_snippets
    Decidim.enable_html_header_snippets = true
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.host!(@organization.host)
    session.get("/")
    assert_equal 200, session.response.status
    assert_includes session.response.body, "window.upgradeProbe = true;"
    assert_includes session.response.body, "decidim-packs"
    session.get("/api/docs")
    assert_equal 200, session.response.status
    assert_includes session.response.body, "GraphQL"
  ensure
    Decidim.enable_html_header_snippets = previous
  end

  def test_system_edit_preserves_reviewed_header_snippet
    previous = Decidim.enable_html_header_snippets
    Decidim.enable_html_header_snippets = true
    form = Decidim::System::UpdateOrganizationForm.from_model(@organization)
    form.name = @organization.name.merge("en" => "Upgrade rehearsal", "pl" => "Proba 0")
    form.short_name = @organization.short_name.merge("en" => "Rehearsal", "pl" => "Proba 0")
    result = nil
    Decidim::System::UpdateOrganization.call(@organization.id, form) do
      on(:ok) { result = :ok }
      on(:invalid) { result = :invalid }
    end
    assert_equal :ok, result, form.errors.full_messages.join(", ")
    assert_equal '<script>window.upgradeProbe = true;</script>', @organization.reload.header_snippets
  ensure
    Decidim.enable_html_header_snippets = previous
  end

  def test_legacy_signed_and_encrypted_cookies_remain_readable
    config = Rails.application.env_config
    previous_env = Rack::MockRequest.env_for("http://emvi-upgrade-0.example.org/").merge(config)
    previous_env["action_dispatch.key_generator"] = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base, iterations: 1000, hash_digest_class: OpenSSL::Digest::SHA1)
    old_request = ActionDispatch::Request.new(previous_env)
    old_request.cookie_jar.encrypted[:encrypted_probe] = { value: { "value" => "preserved" } }
    old_request.cookie_jar.signed[:signed_probe] = { value: { "value" => "preserved" } }
    cookies = old_request.cookie_jar.to_hash.map { |key, value| "#{key}=#{Rack::Utils.escape(value)}" }.join("; ")
    new_request = ActionDispatch::Request.new(Rack::MockRequest.env_for("http://emvi-upgrade-0.example.org/", "HTTP_COOKIE" => cookies).merge(config))
    assert_equal({ "value" => "preserved" }, new_request.cookie_jar.encrypted[:encrypted_probe])
    assert_equal({ "value" => "preserved" }, new_request.cookie_jar.signed[:signed_probe])
  end

  def test_reviewed_translation_calls_for_every_configured_locale
    contracts = {
      "decidim.pages.home.statistics.headline" => {},
      "decidim.admin.imports.notice" => { count: 3, resource_name: "items" },
      "decidim.admin.organization.form.colors.colors_warning_html" => {},
      "decidim.components.add_comment_form.account_message" => {},
      "decidim.debates.actions.new" => {},
      "decidim.meetings.close_meeting_reminder_mailer.close_meeting_reminder.subject" => { meeting_title: "Meeting" },
      "decidim.meetings.registration_mailer.confirmation.confirmed_html" => { title: "Meeting", url: "https://example.org/meeting" },
      "decidim.proposals.admin.proposals_imports.create.success" => {},
      "decidim.sortitions.sortitions.show.candidate_proposals_info" => { taxonomy_labels: "Taxonomy" }
    }
    %w(highlighted_meetings highlighted_results highlighted_proposals).each do |block|
      contracts["decidim.participatory_spaces.#{block}.see_all"] = {}
    end
    %w(invalid success).product(%w(selected unselected)).each do |status, action|
      contracts["decidim.budgets.admin.projects.update_selected.#{status}.#{action}"] = { successful: "A", errored: "B", subject_name: "Projects" }
    end
    %w(email_intro email_outro email_subject notification_title).each do |part|
      contracts["decidim.events.debates.create_debate_event.space_followers.#{part}"] = { resource_path: "/debates/1", resource_url: "https://example.org/debates/1", resource_title: "Debate", participatory_space_title: "Process", participatory_space_url: "https://example.org/processes/example", author_name: "Author", author_nickname: "author", author_path: "/profiles/author", author_url: "https://example.org/profiles/author" }
    end
    Decidim.available_locales.each do |locale|
      contracts.each do |key, args|
        value = I18n.t(key, locale: locale, **args, raise: true)
        assert_kind_of String, value, "#{locale}.#{key}"
        refute_match(/%\{[^}]+\}/, value, "#{locale}.#{key}")
      end
    end
  end

  def test_public_homepage_in_every_production_language
    Decidim::ContentBlock.create!(organization: @organization, scope_name: "homepage", manifest_name: "stats", published_at: Time.current)
    @organization.update_columns(available_locales: %w(bs ca cs de en es fr hr it nl pl pt ro ru el sl sr-CS tr-TR ar-SA fa-IR uk zh-TW))
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.host!(@organization.host)
    @organization.available_locales.each do |locale|
      session.get("/", params: { locale: locale })
      assert_equal 200, session.response.status, locale
      refute_includes session.response.body, "translation_missing", locale
      headline = Nokogiri::HTML(session.response.body).at_css("#statistics .home__section-title")
      refute_nil headline, locale
      refute_match(/%\{[^}]+\}/, headline.text, locale)
    end
  end

  def test_verification_attempts_are_persisted_and_lock_expires
    user = Decidim::User.find_by!(email: "probe0@example.org")
    authorization = Decidim::Authorization.create!(user: user, name: "id_documents")
    assert_equal 5, Decidim.verification_max_failed_attempts
    assert_equal 30.minutes, Decidim.verification_unlock_in
    assert_equal 10, Decidim.verification_code_expiry_minutes
    4.times { authorization.record_failed_attempt! }
    assert_equal 4, authorization.reload.failed_attempts
    refute authorization.locked_for_confirmation?
    authorization.record_failed_attempt!
    assert_equal 5, Decidim::Authorization.find(authorization.id).failed_attempts
    assert authorization.reload.locked_for_confirmation?
    authorization.update_columns(locked_at: 31.minutes.ago)
    authorization.clear_expired_lock!
    assert_nil authorization.reload.locked_at
    assert_equal 0, authorization.failed_attempts
    authorization.record_failed_attempt!
    authorization.reset_failed_attempts!
    assert_equal 0, authorization.reload.failed_attempts
  end

  def test_confirmation_rejects_expired_code_without_sending_sms
    user = Decidim::User.find_by!(email: "probe0@example.org")
    authorization = Decidim::Authorization.create!(user: user, name: "sms", verification_metadata: { secret_code: "SYNTHETIC", code_sent_at: 11.minutes.ago.iso8601 })
    form = Struct.new(:verification_metadata) { def valid? = true }.new({ "secret_code" => "SYNTHETIC" })
    result = nil
    Decidim::Verifications::ConfirmUserAuthorization.call(authorization, form) do
      on(:expired) { result = :expired }
      on(:invalid) { result = :invalid }
      on(:ok) { result = :ok }
    end
    assert_equal :expired, result
    refute authorization.reload.granted?
    assert_empty authorization.verification_metadata
    assert_equal 0, authorization.failed_attempts
  end

  def test_cta_migration_preserves_existing_hero_settings
    hero = Decidim::ContentBlock.find_by!(organization: @organization, scope_name: "homepage", manifest_name: "hero")
    assert_equal "preserve-me", hero[:settings].fetch("existing_setting")
    assert_equal "Mitmachen", hero[:settings].fetch("cta_button_text_de")
    assert_equal "/processes", hero[:settings].fetch("cta_button_path_de")
  end

  def test_upgrade_succeeds_without_a_highlighted_banner_block
    organization = Decidim::Organization.find_by!(host: "emvi-upgrade-1.example.org")
    refute Decidim::ContentBlock.exists?(organization: organization, scope_name: "homepage", manifest_name: "highlighted_content_banner")
    hero = Decidim::ContentBlock.find_by!(organization: organization, scope_name: "homepage", manifest_name: "hero")
    assert_equal "second-hero", hero[:settings].fetch("existing_setting")
  end

  def test_system_action_log_can_have_no_user_after_migration
    columns = ActiveRecord::Base.connection.columns(:decidim_action_logs).index_by(&:name)
    assert columns.fetch("user_id").null
    assert columns.fetch("user_type").null
  end

  def test_release_tasks_with_empty_candidates_preserve_active_records_without_mail
    %w(
      decidim:upgrade:decidim_update_valuators
      decidim:upgrade:decidim_action_log_valuation_assignment
      decidim:upgrade:decidim_paper_trail_valuation_assignment
      decidim:upgrade:fix_nickname_casing
      decidim:upgrade:fix_action_log
      decidim_surveys:upgrade:fix_survey_permissions
      decidim:upgrade:clean:invalid_private_exports
      decidim:upgrade:clean:remove_private_exports_attachments
      decidim:upgrade:remove_deleted_users_left_data
      decidim:upgrade:fix_deleted_private_follows
    ).each do |name|
      Rake::Task[name].reenable
      Rake::Task[name].invoke
    end
    assert Decidim::User.exists?(email: "probe0@example.org")
    assert_equal 643, Decidim::Forms::Response.count
    assert_equal 1, Decidim::Meetings::Registration.count
    assert_empty ActionMailer::Base.deliveries
    assert_empty ActiveJob::Base.queue_adapter.enqueued_jobs
  end
  def test_polish_terms_and_german_statistics
    value = I18n.t("decidim.pages.terms_of_service.refuse.modal_body", locale: :pl, download_your_data_path: "/download-data", delete_path: "/delete-account", raise: true)
    assert_includes value, 'href="/download-data"'
    assert_includes value, 'href="/delete-account"'
    headline = I18n.t("decidim.pages.home.statistics.headline", locale: :de, organization: "EMVI", raise: true)
    refute_includes headline, "Starea"
    assert_equal "Statistiken", headline
  end

  def test_questionnaire_template_can_be_applied_after_response_rename
    template = Decidim::Templates::Template.find_by!(target: "questionnaires")
    assert_equal @organization, template.organization
    assert_equal "Vorlagenfrage", template.templatable.questions.first.body.fetch("de")
    assert_equal "Vorlagenoption", template.templatable.questions.first.response_options.first.body.fetch("de")
    destination = Decidim::Forms::Questionnaire.create!(title: { de: "Ziel" }, questionnaire_for: Decidim::Templates::Template.create!(organization: @organization, name: { de: "Zielvorlage" }, target: "questionnaires"))
    result = nil
    Decidim::Templates::Admin::ApplyQuestionnaireTemplate.call(destination, template) do
      on(:ok) { result = :ok }
      on(:invalid) { result = :invalid }
    end
    assert_equal :ok, result
    assert_equal "Vorlagenfragebogen", destination.reload.title.fetch("de")
    assert_equal "Vorlagenoption", destination.questions.first.response_options.first.body.fetch("de")
    assert_equal 643, Decidim::Forms::Response.count
  end

  def test_groups_identity_membership_comment_gids_and_non_mail_authorship_conversion
    groups = Decidim::User.where("extended_data @> ?", { group: true }.to_json).order(:id).to_a
    assert_equal 2, groups.length
    assert_equal "group0@example.org", groups.first.email
    assert groups.last.extended_data.fetch("patched")
    assert_equal "probe1@example.org", groups.last.extended_data.fetch("previous_email")
    assert_match(/@emvi-upgrade-1.example.org.invalid$/, groups.last.email)
    groups.each do |group|
      membership = ActiveRecord::Base.connection.select_one("SELECT * FROM decidim_user_group_memberships WHERE decidim_user_group_id = #{Integer(group.id)}")
      assert_equal group.organization.id, Decidim::User.find(membership.fetch("decidim_user_id")).organization.id
      assert group.officialized_at
    end
    Decidim::Comments::Comment.find_each do |comment|
      assert_includes comment.body.fetch("de"), "gid://decidim/Decidim::User/"
      assert_includes comment.body.dig("machine_translations", "en"), "gid://decidim/Decidim::User/"
    end
    %w[decidim:upgrade:user_groups:transfer_user_groups_authorships decidim:upgrade:user_groups:fix_user_groups_action_logs].each do |name|
      Rake::Task[name].reenable
      Rake::Task[name].invoke
    end
    Decidim::Proposals::Proposal.find_each do |proposal|
      authorship = proposal.coauthorships.first
      assert_equal proposal.organization.id, authorship.author.organization.id
      assert authorship.author.extended_data.fetch("group")
    end
    Decidim::Comments::Comment.find_each { |comment| assert comment.author.extended_data.fetch("group") }
    assert_empty ActionMailer::Base.deliveries
    refute ActiveJob::Base.queue_adapter.enqueued_jobs.any? { |job| job[:job] <= ActionMailer::MailDeliveryJob }
  end
  def invoke(name, *args)
    task = Rake::Task[name]
    task.reenable
    task.invoke(*args)
  end

  def import_taxonomies
    invoke("decidim:taxonomies:make_plan")
    Decidim::Organization.order(:id).each do |organization|
      plan = Rails.root.join("tmp/taxonomies/#{organization.host}_plan.json")
      data = JSON.parse(plan.read)
      assert data.fetch("imported_taxonomies").values.any?(&:present?), "expected a nonempty import"
      invoke("decidim:taxonomies:import_plan", plan.to_s)
      result = Rails.root.join("tmp/taxonomies/#{organization.host}_result.json")
      data = JSON.parse(result.read)
      assert_empty data.fetch("failed_resources")
      assert_empty data.fetch("failed_components")

    end
  end

  def test_nonempty_taxonomy_import_preserves_assignments_and_organization_boundaries
    import_taxonomies
    Decidim::Organization.order(:id).each do |organization|
      process = Decidim::ParticipatoryProcess.find_by!(decidim_organization_id: organization.id)
      proposal = Decidim::Proposals::Proposal.find_by!(decidim_component_id: process.components.find_by!(manifest_name: "proposals").id)
      assert_includes process.taxonomies.map { |t| t.name["de"] }, "Nord"
      assert_includes process.taxonomies.map { |t| t.name["de"] }, "Bezirk"
      assert_includes proposal.taxonomies.map { |t| t.name["de"] }, "Viertel"
      assert_includes proposal.taxonomies.map { |t| t.name["de"] }, "Radwege > Sicherheit"
      assert_equal [organization.id], proposal.taxonomies.pluck(:decidim_organization_id).uniq
      category = proposal.taxonomies.find { |t| t.name["de"] == "Radwege > Sicherheit" }
      assert_equal "Bezpieczenstwo", category.name["pl"]

      filters = process.components.find_by!(manifest_name: "proposals").settings.taxonomy_filters
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


end
