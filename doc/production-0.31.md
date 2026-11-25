# EMVI 0.31 production preparation

Prepared 2026-11-25 on `prepare/emvi-0.31-production`. This request covers preparation. Production database changes, deployment and notification/password emails have not been authorized or executed. Alex accepted staging login/uploads on 0.31.9.

## Production baseline and release blocker

Production still runs `9e35d853ee52d07727842fb6e1d8d51a05046176`, Ruby 3.3.14, fork 0.30.9 at `a01873761bc05359ec5937268c0d982e1d3bfdbf`. The database has seven organizations (IDs 1, 2, 3, 4, 5, 6, 39), 33 categories, ten scopes, 23 areas, zero taxonomies, 643 answers and six registrations. Normal user counts can change with ongoing traffic; preservation baselines must be recaptured during maintenance. The latest inspected job sample has zero active jobs and 186 existing MailDeliveryJob / Net::ReadTimeout failures; do not retry them.

**Do not promote existing staging image `423f668f` / old rollout jobs 29390–29393.** Berlin (organization 5) deliberately has no hero block. The unmodified `MoveCtaToHeroContentBlock` migration dereferences nil and would abort production. This branch changes it to find or initialize a hero: existing blocks keep their IDs/settings/publication, while a missing block retains legacy CTA data as an **unpublished** block. No new homepage section becomes visible and the old CTA columns can be removed without discarding those values. A fresh image containing this fix must pass CI, then main/staging before production. Changing the already-applied staging migration file does not rerun it there.

## Taxonomy findings and proposed corrections

All production inspections use `REPEATABLE READ` plus `SET TRANSACTION READ ONLY`, a statement timeout and a lock timeout. Aggregate output excludes names, emails, content titles and content/author reference IDs. The collector rejects private fields, email/URL/GID strings before writing local evidence.

| Legacy model | Source records | Native plan coverage | Corrected coverage |
| --- | ---: | ---: | ---: |
| Scope | 10 | 9 | 10 |
| Area | 23 | 13 | 23 |
| Category | 33 | 28 | 33 |

The 16 omitted records belong to organization 6. Its default language is French, while the affected labels are available in English. The native exporter keys items by the missing French label, so entries overwrite each other. Some omitted records have existing resource assignments; they cannot be discarded as unused data.

`Emvi::Maintenance::TaxonomyPlanning` temporarily supplies existing translated labels in returned Hash copies while building the plan. It does not save legacy records or run machine translation. It also:

- Repairs eleven area-filter paths where the native planner uses the type's singular name but creates the hierarchy under its plural name.
- Separates conflicting internal filter identities in organizations 5 and 6. Public labels are retained. Berlin's two source filters must not become one filter with the union of both item lists; components with different scope restrictions must not share a widened filter.
- Keeps the proposed shared German root label where its child paths are disjoint. The final audit finds zero colliding child paths, missing filter paths, conflicting filter definitions, invalid/cross-organization references or conflicting assignments to singular taxonomy fields. The concrete labels still need human review before import; alternative root names must be agreed before import, not introduced by blindly regenerating/reimporting plans later.

The corrected audit covers 791 distinct resource/component references within the seven plans and 32 source filter definitions. These are reference counts, not counts of proposals or newly created filters. Five model sections are present per organization; retain all **35 section reports**, including empty sections. The stock task overwrites the per-organization result file for each section and cannot serve as the sole audit record.

The existing maintenance adapter must remain loaded to preserve earlier component filter assignments and normalize nil/empty manifest lists on repeated imports.

## Atomic 0.30 import and metrics

The 0.30 taxonomy model fills ancestry in `after_create_commit`. Simply wrapping the stock importer in an outer transaction leaves nil ancestor IDs and fails on the next child. `Emvi::Maintenance::AtomicTaxonomyImport.enable!` completes that same native ancestry hook immediately for newly created nodes with nil ancestor IDs. It is restricted to 0.30.9, enabled explicitly for the maintenance process, and is not enabled during web boot or read-only planning.

The local tests cover a real joining outer transaction, complete rollback on failure, repeated imports, tenant isolation, independent scope filters, area filter paths and preserved metric assignments. Use a transaction per organization spanning all five sections and its metric updates; stop on any error or nonempty failed-resource/component list. Successful earlier organizations remain committed if a later organization fails. Do not proceed to 0.31 until all organizations pass. Retry/resume only after diagnosis, or restore the pre-import backup while application writes remain paused.

Merge taxonomy maps from every section. Apply category-to-metric mappings while still on 0.30.9, restricted to the organization. The 0.31 runtime no longer supplies the old metrics task. Preserve all section reports outside the maintenance pod. Do not run unreviewed broad cleanup tasks.

## Berlin group

Production has one group, ID 257, one confirmed active creator membership and no authored-content references through `decidim_user_group_id`. Its email is nonempty but collides with another account in the same organization; that account is not the creator. The group has no password.

The 0.31 schema migration converts the same row into a regular user, preserves the group marker and previous email, and substitutes an `.invalid` address for the collision. This behavior was rehearsed with a separate creator and colliding ordinary account; ordinary identities/password fields and memberships are preserved.

Proposed handling is to preserve this unused historical profile without sending access mail or generating shared credentials during the technical rollout. Confirm the group identity/contact ownership before choosing whether a usable group login is needed, an alternative address should be assigned, or the existing ordinary account is sufficient. Do not delete, merge or block accounts as part of preparation.

Do not run `decidim:upgrade:user_groups:remove`: it includes password generation and emails. After deployment, inspect fresh candidates and run only reviewed non-mail authorship/action-log corrections. Group access/password/member notifications require an explicit recipient/content decision; the ordinary account with the colliding email must not be overwritten.

## Validation

Six 0.30 import tests pass **181 assertions**. The full synthetic rehearsal imports classifications for three tenants (including missing French labels, distinct area singular/plural names and an unused group whose email belongs to a nonmember), then runs **39 schema and ten data migrations** to 0.31.9.

All **23 post-upgrade checks** pass: taxonomy IDs/names/assignments and component filters, 643 answer identities/content, registrations, memberships and ordinary identities; retained group ID/collision history without a new password; preserved CTA values in an unpublished hero; unchanged published block list; public rendering without that hero and positive rendering of an existing published hero. No login/upload flow or SMTP delivery was tested. Four dummy production boot scenarios still pass six tests/38 assertions each, including SMTP read_timeout 15 and preserved transport settings.

Only synthetic data was used. The extra local database is `emvi_030_plan_rehearsal` on the owned PostgreSQL socket `/private/tmp/emvi031-pg/socket`, port 55441. The 0.30 reference worktree uses explicit Ruby 3.3.14/Node 22.14.0 because its old mise.toml is stale. The local platform addition does not change gem versions or framework revision. Do not deploy this reference branch.

Run the focused tests before migrating that disposable database; after migration use the post-0.31 verifier. Scripts enforce the database/socket/environment. Preparation code lives in this branch; the reference worktree is `.worktrees/emvi-0.30-production-prep` at the original production baseline.

## Safe read-only audit

From this repository:

```sh
python3 script/collect_emvi_031_preflight.py --proposed \
  --output /Users/alex/Documents/Projekte/decidim/.upgrade-backups/emvi031-production-preparation-20261125/aggregate-proposed-plans.json
```

The fixed context is `kubernetes-admin@cluster1`, namespace `decidim-emvi-production`. The collector enables no imports, jobs, migrations or emails. No customer answer/message text or complete database was copied locally.

A proposed local export of the original plans/contact details was rejected by automatic approval review and did not execute. Only aggregate findings are retained. Final human review of the concrete taxonomy labels and the group/contact mapping remains pending explicit approval for that payload and its private local destination. No contact details belong in Git or this runbook.

## Proposed production sequence

1. Review/merge the missing-hero fix and preparation MR after CI. Let the new main image deploy to staging and independently verify its digest, readiness, SMTP settings and public pages. Preserve the already completed user acceptance; inspect any additional actual runtime changes separately. Record the new production job; do not reuse the old `423f668f` rollout.
2. After private-export approval, generate the seven corrected plans under read-only protection, strip unused resource-title values and organization display names, preserve their checksums and review their concrete labels/relationships. Separately review the minimal group/creator/colliding-account contact mapping. Agree the access/mail handling. This approval is distinct from permission to mutate production.
3. Obtain production execution authorization and a maintenance window. Recapture counts, identity/content/attachment digests, plan fingerprints and job candidates. Stop application writes and old GoodJob workers; use a maintenance workload with the existing **0.30** image/environment, excluded from public Services. The current public Service selector includes `app=production,tier=web,track=stable`; a maintenance workload must not match it. Do not start a 0.31 server against the old schema.
4. Create and verify a fresh CNPG backup **before taxonomy import**. The latest observed completed backup was `weekly-backup-20261122021000`, ID `20261122T021000`, completed 2026-11-22 02:10:14 UTC. It is evidence of the existing backup setup, not the fresh upgrade backup. CNPG reports three ready instances. Status/WAL metadata is not proof of a tested restore.
5. Load the existing filter-union adapter and the explicit atomic-import module in the old maintenance runtime. Reject drift against the reviewed source plans. Import each approved organization plan transactionally, collect every section's results, update metrics and verify source coverage, taxonomy/resource assignments, component restrictions and absence of cross-tenant references. Leave legacy source classifications intact. Verify all seven organizations before continuing.
6. Make a **second fresh backup after verified taxonomy conversion and before 0.31 schema changes**. Keep old web/GoodJob paused. Deploy the newly tested fixed image directly at 100%; avoid mixed 0.30/0.31 workers around table renames. Override `AUTO_DEVOPS_ATOMIC_RELEASE=false` for the schema-changing job. The managed DB_MIGRATE already invokes `db:migrate data:migrate`; no further Terraform change is required.
7. Verify all migrations, preserved data/identities/attachments, new group markers and the unpublished missing hero. Run only reviewed release tasks with fresh candidates; do not invoke group mail/password aggregates or retry the historical mail failures. Check all tenant homepages, Berlin map, languages, filters, forms, jobs and SMTP settings. Restore normal service after verification and monitor the new pods.
8. If the 0.31 migration fails, keep old workers stopped. Diagnose before taking recovery action; an old-image Helm rollback against renamed tables is unsafe. Recovery pairs the pre-0.31 backup with the corresponding 0.30 image. Retain the pre-taxonomy backup as a separate earlier recovery point. Do not use down-migrations as a substitute for an agreed restore procedure.
