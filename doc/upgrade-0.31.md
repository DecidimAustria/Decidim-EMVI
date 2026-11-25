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

The default is 15 seconds; an explicit environment value overrides it. Preserve the previous application default `SMTP_STARTTLS_AUTO=false`; explicit `true` still enables STARTTLS. The actual SMTP transport mode and unchanged five-second connection timeout are tested without connecting. Base 10 permits `037` as 37 seconds. Invalid input fails boot. No Terraform variable is needed for the default. Both Kubernetes staging and production use Rails production mode. This is a read timeout, not a delivery guarantee; historical failed mail is not retried or resent. No SMTP connection or test message is used in validation.

## Data and application compatibility

The official generator adds **39 schema migrations** (34 framework and five Awesome) and **ten engine data migrations**. Both empty and populated 0.30 schema rehearsals complete. Ten historical migration files contain substantive upstream updates; comment-only generator rewrites are restored to their original bytes. `db/schema.rb` and `db/data_schema.rb` describe the migrated empty fixture, without customer data.

The populated fixture contains two tenants, nested categories/scopes and typed areas, group-authored proposals/comments, a duplicate-email group case, 643 answers/choices, one meeting registration, historical answer references and a questionnaire template. Verification checks response IDs/content/associations, template application, GID changes and non-mail group-authorship conversion, tenant boundaries, snippets, cookie compatibility, verification lock/expiry behavior and all configured locale call sites/homepages. The existing Berlin conversion/render/restore tests use the previously authorized private public-HTML fixture; no Berlin production record is changed.

Keep the existing maintenance-only taxonomy adapter enabled for 0.31.9. The synthetic repeat-import test reproduces duplicate filters without the adapter's omitted-manifest normalization. The adapter also retains earlier component filters; regression checks explicitly inspect the proposals component. Actual production classification import is a separate prerequisite below. 0.31 no longer provides the old `decidim:taxonomies:update_metrics` task; do that work on 0.30, not by replaying the old runbook after upgrade.

Replace generated 0.30 interpolation repairs with 120 reviewed 0.31 repairs across 18 languages; the generator is idempotent. Preserve customer wording and the Polish terms override. The target upstream German statistics heading is `Statistiken`, rather than the defective Romanian value in 0.30.9. The nil-query translation-bar guard remains necessary through 0.31.9.

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

**22 upgrade tests/8,079 assertions and eight Berlin map tests/127 assertions pass.** Production assets/API documentation, Zeitwerk eager loading and clean npm ci pass with dummy credentials and an unreachable database. Four production-config scenarios pass six tests/38 assertions each: default settings, disabled STARTTLS/translation, explicit timeout `037` and explicitly enabled STARTTLS. The SMTP transport object's timeout is checked without connecting. Invalid SMTP_READ_TIMEOUT is rejected. npm audit reports 74 findings (2 low, 42 moderate, 30 high, zero critical); no broad audit fix is applied. CI image scans must still be reviewed.

## Initial staging rollout (schema migration)

1. The companion Terraform [MR !7](https://gitlab.webface.at/mitgestalten/projects_tf/-/merge_requests/7) changes only EMVI's DB_MIGRATE to `RAILS_ENV=production bundle exec rails db:migrate data:migrate`. The full refreshed plan has one in-place update and no additions/deletions. Apply only once the new application image passes; the protected-main read-only plan can run earlier. Do not rerun old 0.30 deployment jobs after apply.
2. Publish and review the app MR image/scans. The temporary `upgrade_gate` parent job emits a fail-closed main-only manual staging overlay only when the planner schedules an image build. MR and documentation-only pipelines emit no staging job. Parent, MR, main and docs-only main CI lint pass. Production remains manual. Remove this temporary gate after initial technical staging acceptance.
3. Build protected main before pausing the old application. Check the immutable image, assets, runtime, SMTP default and PNG/MSL policy using a disposable probe with dummy environment values and no application secrets/service-account token.
4. Recheck staging counts/jobs and record preservation digests. Baseline on 2026-11-25 is 0.30.9/Ruby 3.3.14/Rails 7.0.10, three users, zero groups/memberships/responses/registrations/templates/classifications, 43 versions and no active/failed GoodJob jobs. The single organization has hero/banner blocks. Login/uploads are Alex's checks.
5. Stop old staging web/GoodJob immediately before the migration; make and verify a fresh CNPG backup including backup ID and WAL bounds. Explicit context `kubernetes-admin@cluster1`, namespace `decidim-emvi-staging`. Run only the gated staging job. Override `AUTO_DEVOPS_ATOMIC_RELEASE=false` for this one schema-changing job to prevent an automatic old-image rollback against renamed tables. A failed migration requires diagnosis and possibly coordinated DB/image recovery.
6. Verify migration-job success, 39 schema/ten data migrations, new web/worker images/readiness/restarts, data/block digests, public locales/API/assets/404s and recent logs. Execute only reviewed release tasks with the observed staging candidate counts. Do not invoke the mail-producing aggregate user-group removal task or broad attachment cleanup. Leave login/uploads and test mail to Alex; do not retry old mail jobs.

## Production prerequisites — not authorized by this staging request

Production remains on the patched 0.30.9 baseline until separately agreed. On 2026-11-25 its seven organizations have **33 categories, ten scopes, 23 areas and zero taxonomies**. Complete and verify the reviewed 0.30 classification conversion before promotion, especially German scope/area root-name collisions and preservation of all component filters. Preserve plans and every import section's result; the final result JSON alone can hide earlier failures. Do not import or change customer classifications during this staging task.

Berlin has **one user group and one membership**. Review its email/ownership/authorship and coordinate notifications/password-reset handling; the aggregate `decidim:upgrade:user_groups:remove` can email owners/members and must not run casually. Production has **643 form answers and six registrations**; preserve content/identity digests before the form-table renames. Check Templates and all seven organizations, Berlin map/locales/Polish text, integrations, snippets and storage links.

All 178 previously observed failed jobs are MailDeliveryJob / Net::ReadTimeout, with no unfinished jobs. They remain historical failures; the timeout change does not resend them. A later production rollout requires a separate fresh backup and coordinated migration window, staging login/upload acceptance and explicit production authorization.

## Staging verification and SMTP follow-up — 2026-11-25

Initial app MR !274 merged as `13b654df`. Main build 29368 and its isolated immutable-image probe passed; the main-image digest is `04a5bfb72084a11e065fd5725af479e9fc9c2db97e4fab947e427cef7eb92655`. Terraform !7 merged as `470e6207`; plan 29363/apply 29364 changed exactly the one migration-command variable. Fresh backup `pre-0319-upgrade-20261125205535` completed before staging retry 29374. All 39 schema/ten data migrations completed without errors, and both new-image Deployments became ready.

The first attempt, job 29369, failed rendering Helm YAML because an extra one-off database guard was quoted incorrectly. No migration Job was created; the original 0.30.9 pods were restored, their unchanged schema/counts verified, then a second fresh backup was made. The successful retry used the standard managed migration command. The earlier backup `pre-0319-upgrade-20261125205002` is also retained. Neither attempt touched production.

The live configuration comparison identified an unintended STARTTLS default change from false to true. This follow-up restores the legacy false default in production.rb while retaining explicit ENV overrides and the requested 15-second read timeout. Rails 7.2 also exposes `open_timeout: 5` explicitly; Mail 2.9.1, used before and after, already had that effective connection timeout. SMTP credentials and mailer identity digests are unchanged. Corrective build 29378 and automatic staging 29379 succeeded on image `744df333`. The strict live comparison confirms preserved configuration/SMTP/identity digests, actual STARTTLS false and open_timeout 5, with the requested read_timeout 15. No test email or failed-mail retry was performed.

The temporary first-upgrade staging gate is removed in this follow-up. Schema/data migrations are already applied, so normal automatic staging is restored; production remains manual and is not authorized by this task. Further rollout results are recorded below when independently checked. Alex retains login/upload acceptance. The eight critical Debian scanner findings use the same versions as the old staging image; they remain a separate base-image follow-up. Report collection succeeded, with a legacy RuboCop style backlog rather than a zero-offense result.


### Homepage statistics compatibility

Anonymous browser verification found that the 0.31 statistics cell no longer passes `organization` to its headline. Retained Arabic, Persian and Turkish text exposed the raw placeholder. The compatibility generator now reuses each language’s existing translated generic statistics label for these three entries. The regression suite renders the actual statistics block in all 22 configured languages and rejects unexpanded placeholders, in addition to testing the no-argument translation contract. Customer wording elsewhere is preserved.


### Final independent staging verification

Build 29394 / staging 29389 in main pipeline 7480 / child 7481 succeeded. Runtime commit `423f668f56a4b80b5cf3e930e9cb05eca94d7668`, registry/pod digest `sha256:e1b2113d577e3fdc28d5e6d119ccea8f85f05fa012872e1fdb8b2910a17cdee7`, Helm revision 118. Web/GoodJob are each 1/1 ready without restarts. All compared configuration, SMTP credential/identity, user/password, storage and hero/banner preservation checks pass; actual read_timeout 15, STARTTLS false and open_timeout 5 are confirmed. All schema/ten data migrations are up, and GoodJob has zero active/failed jobs.

Anonymous checks pass all 13 staging languages, actual statistics headings, assets, API documentation/read-only GraphQL and expected 404s. Arabic browser verification confirms the native language label, corrected statistics headline, RTL and no console errors. Three targeted statistics-cache checks found no stale fragments; no deletion was needed. Final bounded web/worker logs contain no HTTP 5xx, SMTP ReadTimeout or job-error markers; expected routing errors render 404. The existing critical-scan Debian package versions still match the original staging baseline.

The locale generator now has 120 repairs across 18 languages, zero second-run changes; the 22-test suite passes 8,079 assertions including actual statistics rendering in all 22 configured languages. GitLab maintenance caused artifact-only failures in plan 29384/build 29388; safe retries 29386/29394 passed without source changes. Original production image `9e35d853` remains ready and unchanged. Alex retains login/upload acceptance and production promotion requires the separately reviewed prerequisites above.
