# EMVI 0.31.9 upgrade

Prepared on 2026-11-25 from current main `9e35d853ee52d07727842fb6e1d8d51a05046176` in the isolated `upgrade/emvi-0.31.9` worktree. The original checkout and other worktrees are unchanged. Alex authorizes preparation and staging deployment; production promotion is separate.

## Dependencies and configuration

Use official RubyGems Decidim, all bundled engines and Templates **0.31.9**, Rails **7.2.4**, Shakapacker gem/npm **8.3.0**, Awesome **0.14.5**, Ruby **3.3.14** and Node **22.14.0**. Amazon Translate remains 0.3.2. Keep current main's ImageMagick security policy and Sentry integration. The framework fork is no longer required for this target.

Common locked gem downgrades are deliberate compatibility requirements: `rack-proxy` 2.0.1 → 0.8.3 (Decidim requires ~> 0.8.3, < 1.0) and development/test `minitest` 6.0.6 → 5.27.0 (Rails 7.2.4 requires < 6). The production development proxy remains absent. Other common gem versions do not decrease. Published framework npm packages are pinned to 0.31.9; Tom Select is pinned to Decidim's own 2.2.2 dependency. EMVI's previously resolved 2.4.3 CSS fails Sass compilation with incompatible `6px`/unitless `0` arithmetic. Clean production compilation succeeds with 2.2.2. No Tom Select advisory is reported by npm audit. Superseded copied framework `packages/` are removed; compiled assets, caches and node_modules stay ignored.

Rails 7.2 replaces Rails secrets access with native Decidim/ENV configuration. Preserve MinIO private/path-style storage, Sentinel cache/cable, HERE fallback, translation defaults, all 22 selectable languages and EMVI's CDN/analytics CSP extras. Regional parent languages load after Decidim's own I18n setup, keeping the Arabic menu label. Cookie rotation retains SHA1-derived cookies without changing SECRET_KEY_BASE.

Production-mode SMTP configuration now includes:

```ruby
:read_timeout => Integer(ENV.fetch("SMTP_READ_TIMEOUT", "15"), 10),
```

The default is 15 seconds; an explicit environment value overrides it. Base 10 permits `037` as 37 seconds. Invalid input fails boot. No Terraform variable is needed for the default. Both Kubernetes staging and production use Rails production mode. This is a read timeout, not a delivery guarantee; historical failed mail is not retried or resent. No SMTP connection or test message is used in validation.

## Data and application compatibility

The official generator adds **39 schema migrations** (34 framework and five Awesome) and **ten engine data migrations**. Both empty and populated 0.30 schema rehearsals complete. Ten historical migration files contain substantive upstream updates; comment-only generator rewrites are restored to their original bytes. `db/schema.rb` and `db/data_schema.rb` describe the migrated empty fixture, without customer data.

The populated fixture contains two tenants, nested categories/scopes and typed areas, group-authored proposals/comments, a duplicate-email group case, 643 answers/choices, one meeting registration, historical answer references and a questionnaire template. Verification checks response IDs/content/associations, template application, GID changes and non-mail group-authorship conversion, tenant boundaries, snippets, cookie compatibility, verification lock/expiry behavior and all configured locale call sites/homepages. The existing Berlin conversion/render/restore tests use the previously authorized private public-HTML fixture; no Berlin production record is changed.

Keep the existing maintenance-only taxonomy adapter enabled for 0.31.9. The synthetic repeat-import test reproduces duplicate filters without the adapter's omitted-manifest normalization. The adapter also retains earlier component filters; regression checks explicitly inspect the proposals component. Actual production classification import is a separate prerequisite below. 0.31 no longer provides the old `decidim:taxonomies:update_metrics` task; do that work on 0.30, not by replaying the old runbook after upgrade.

Replace generated 0.30 interpolation repairs with 117 reviewed 0.31 repairs across 18 languages; the generator is idempotent. Preserve customer wording and the Polish terms override. The target upstream German statistics heading is `Statistiken`, rather than the defective Romanian value in 0.30.9. The nil-query translation-bar guard remains necessary through 0.31.9.

## Local checks

The dedicated PostgreSQL 14 cluster uses `/private/tmp/emvi031-pg/socket`, port 55441, role `decidim_upgrade`, with no TCP listener. The two databases are `emvi_031_data_rehearsal` and `emvi_031_empty_rehearsal`; they contain only synthetic records. `script/seed_031_rehearsal.rb` refuses a nonempty DB and reads the schema/migration baseline from the original main commit. Use standalone Ruby for seeding, not Rails runner. The test scripts guard the database name, socket and Rails environment.

```sh
mise exec -- bundle exec ruby script/seed_031_rehearsal.rb
REHEARSAL_EMPTY=1 mise exec -- bundle exec ruby script/seed_031_rehearsal.rb

export RAILS_ENV=test DISABLE_SPRING=1 STORAGE_PROVIDER=local SENTRY_DSN=''
export AWS_EC2_METADATA_DISABLED=true AWS_REGION=eu-central-1
export AWS_ACCESS_KEY_ID=local-test AWS_SECRET_ACCESS_KEY=local-test
export DATABASE_URL='postgresql://decidim_upgrade@localhost/emvi_031_data_rehearsal?host=/private/tmp/emvi031-pg/socket&port=55441'
mise exec -- bin/rails db:migrate data:migrate
mise exec -- bin/rails runner script/verify_031_upgrade.rb
# Set BERLIN_LEGACY_FIXTURE to the authorized private block-63 JSON export:
mise exec -- bin/rails runner script/verify_berlin_map.rb
```

**22 upgrade tests/7,947 assertions and eight Berlin map tests/127 assertions pass.** Production assets/API documentation, Zeitwerk eager loading and clean npm ci pass with dummy credentials and an unreachable database. Three production-config scenarios pass six tests/36 assertions each: default timeout, disabled STARTTLS/translation and explicit timeout `037`. The SMTP transport object's timeout is checked without connecting. Invalid SMTP_READ_TIMEOUT is rejected. npm audit reports 74 findings (2 low, 42 moderate, 30 high, zero critical); no broad audit fix is applied. CI image scans must still be reviewed.

## Staging rollout

1. The companion Terraform [MR !7](https://gitlab.webface.at/mitgestalten/projects_tf/-/merge_requests/7) changes only EMVI's DB_MIGRATE to `RAILS_ENV=production bundle exec rails db:migrate data:migrate`. The full refreshed plan has one in-place update and no additions/deletions. Merge/apply only once the new application image passes. Do not rerun old 0.30 deployment jobs after apply.
2. Publish and review the app MR image/scans. The temporary `upgrade_gate` parent job emits a fail-closed main-only manual staging overlay only when the planner schedules an image build. MR and documentation-only pipelines emit no staging job. Parent, MR, main and docs-only main CI lint pass. Production remains manual. Remove this temporary gate after initial technical staging acceptance.
3. Build protected main before pausing the old application. Check the immutable image, assets, runtime, SMTP default and PNG/MSL policy using a disposable probe with dummy environment values and no application secrets/service-account token.
4. Recheck staging counts/jobs and record preservation digests. Baseline on 2026-11-25 is 0.30.9/Ruby 3.3.14/Rails 7.0.10, three users, zero groups/memberships/responses/registrations/templates/classifications, 43 versions and no active/failed GoodJob jobs. The single organization has hero/banner blocks. Login/uploads are Alex's checks.
5. Stop old staging web/GoodJob immediately before the migration; make and verify a fresh CNPG backup including backup ID and WAL bounds. Explicit context `kubernetes-admin@cluster1`, namespace `decidim-emvi-staging`. Run only the gated staging job. Override `AUTO_DEVOPS_ATOMIC_RELEASE=false` for this one schema-changing job to prevent an automatic old-image rollback against renamed tables. A failed migration requires diagnosis and possibly coordinated DB/image recovery.
6. Verify migration-job success, 39 schema/ten data migrations, new web/worker images/readiness/restarts, data/block digests, public locales/API/assets/404s and recent logs. Execute only reviewed release tasks with the observed staging candidate counts. Do not invoke the mail-producing aggregate user-group removal task or broad attachment cleanup. Leave login/uploads and test mail to Alex; do not retry old mail jobs.

## Production prerequisites — not authorized by this staging request

Production remains on the patched 0.30.9 baseline until separately agreed. On 2026-11-25 its seven organizations have **33 categories, ten scopes, 23 areas and zero taxonomies**. Complete and verify the reviewed 0.30 classification conversion before promotion, especially German scope/area root-name collisions and preservation of all component filters. Preserve plans and every import section's result; the final result JSON alone can hide earlier failures. Do not import or change customer classifications during this staging task.

Berlin has **one user group and one membership**. Review its email/ownership/authorship and coordinate notifications/password-reset handling; the aggregate `decidim:upgrade:user_groups:remove` can email owners/members and must not run casually. Production has **643 form answers and six registrations**; preserve content/identity digests before the form-table renames. Check Templates and all seven organizations, Berlin map/locales/Polish text, integrations, snippets and storage links.

All 178 previously observed failed jobs are MailDeliveryJob / Net::ReadTimeout, with no unfinished jobs. They remain historical failures; the timeout change does not resend them. A later production rollout requires a separate fresh backup and coordinated migration window, staging login/upload acceptance and explicit production authorization.
