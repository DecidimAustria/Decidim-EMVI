# EMVI 0.31.9 production

## Verified result, 2026-11-26

Alex explicitly authorized the production upgrade on 2026-11-26 after the seven taxonomy plans and Berlin contact mapping had passed private review. Production now runs official Decidim/Templates **0.31.9**, Ruby **3.3.14**, Rails **7.2.4**, Shakapacker **8.3.0** and Awesome **0.14.5**.

Deployed main/runtime: `db88a1714a087e43aeb5213c8e0ec12f2372f71e`; immutable image digest: `sha256:9bf2479f9b613fa939550be11aef3844b930b0882373c30ca609ae18ae79f37d`. GitLab main pipeline 7487 / child 7488, **production rollout 100% job 29413**, succeeded at **08:36:30 UTC**. Helm release `production` is deployed at revision **86**. Web and GoodJob each have one ready replica, matching registry image IDs and zero restarts. Earlier incremental jobs 29410–29412 remain unplayed. Do not rerun obsolete 0.30 or initial 0.31 deployment jobs.

Context `kubernetes-admin@cluster1`, namespace `decidim-emvi-production`. No infrastructure changes or new image build were needed. The deployment job explicitly used `AUTO_DEVOPS_ATOMIC_RELEASE=false` and managed `RAILS_ENV=production bundle exec rails db:migrate data:migrate`.

## Maintenance and two recovery points

The isolated old-image maintenance pod matched no Kubernetes Service and ran no server or worker. Production web/GoodJob were scaled to zero at approximately 08:25 UTC; the old pods were fully removed before the authoritative preservation baseline and backup. New web became ready around 08:35 UTC. Normal customer traffic can resume once the new schema and ready web are in place. No mixed 0.30/0.31 workers ran around the table renames.

The two CNPG backups completed successfully with backup IDs and WAL bounds:

- Before taxonomy import: `pre-0319-taxonomy-20261126082539`, backup ID `20261126T082540`, completed `2026-11-26T08:29:44Z`, WAL `0000009300000164000000DC` through `0000009300000164000000DC`.
- After verified taxonomy import, before 0.31 schema migration: `pre-0319-schema-20261126083245`, backup ID `20261126T083245`, completed `2026-11-26T08:32:59Z`, WAL `0000009300000164000000DC` through `0000009300000164000000DD`.

These are database recovery points with verified completion metadata, not a tested restore or a local copy of object storage. For recovery, pair the pre-schema backup with the corresponding old 0.30 image; do not run an old-image Helm rollback against renamed 0.31 tables. The pre-taxonomy backup is the separate earlier recovery point. Keep both backups.

## Taxonomy conversion and Berlin filter correction

All seven reviewed native/proposed structural fingerprints matched immediately before any production write. The old 0.30 runtime imported each organization atomically, preserving all **35 section reports**. Actual resource assignments, allowed filter item sets, component filter unions and metric mappings were verified before each commit, including protection against native resource updates returning false without reporting failure.

The first attempt stopped before the first organization committed because production machine translation was enabled and the test queue detected translation jobs. Its transaction fully rolled back. No real jobs or mail were queued. The retry explicitly disabled machine translation only in the isolated maintenance process; saved translations were retained. All organizations imported successfully with zero failed resources/components and zero queued jobs. Web runtime machine translation configuration remained unchanged.

The import created 80 taxonomy nodes, 32 filters and 973 taxonomizations. All **66 legacy classifications** are covered. Existing English labels preserve the French-default tenant's 16 otherwise omitted records; eleven area filter paths and conflicting filter identities are corrected. Category metric updates ran while the 0.30 Metric model was still available. Old classifications were retained.

The final public filter check disproved the preparation's assumption that Berlin could safely share one root. Although the filter definitions were separate, Decidim combines selections within the same root with OR. This widened a combined level/district selection and produced duplicate filter DOM IDs. The earlier shared-root recommendation in preparation documents is superseded.

A targeted transactional correction was first rehearsed locally, including forced rollback, three synthetic OR matches becoming one AND match, and stable assignment/filter IDs. Production then retained level root **69**, moved the twelve district nodes to new root **108**, and reassigned existing district filter **28** to it. Level filter **27**, all leaf taxonomy IDs, taxonomizations, filter-item IDs and public filter labels were preserved. No original classification was renamed or merged. All **24 combinations** match the legacy scope/area intersections; all other tenants were verified unchanged. A final read-only check validates the fourteen Berlin source nodes, 423 assignment edges and both filter definitions. Final totals are **81 taxonomies, 32 filters and 973 taxonomizations**.

Do not replay the old shared-root plans or blindly regenerate/reimport them. The private final Berlin layout and the explicit partition result are preserved separately from the original reviewed plans.

## Schema, data and release tasks

Migration pod `production-db-migrate-qhctc` completed **39 schema and ten data migrations**, with all ten data statuses up and no pending schema migrations. The log contains 49 successful completion markers and no migration error markers.

Ten reviewed release tasks completed: evaluator-role migration, valuation action-log/history names, nickname casing, menu-hidden log visibility, survey permissions, the three non-mail user-group corrections, and private follow cleanup. **16** `valuator` roles became `evaluator`; four obsolete group notifications were removed. The official private-follow task's **255** jobs were completed inline with mail/unknown jobs guarded; it removed **13** follows that no longer belonged to permitted private-space participants. No jobs remain active.

The mail/password group aggregate was not invoked. Group **257** retains its ID/name/nickname, group marker, patched collision history, empty password and `.invalid` collision address. Both ordinary accounts, their emails and password digests, and the single membership are preserved. Exact contacts stay in the previously authorized private folder, excluded from Git and these documents.

Optional older maintenance was left intact: two deleted users still have 13 historical versions and one notification; two private exports with their attachments remain. Deleted-user history cleanup, expired/private-export attachment purging, SMS revocation and broad storage cleanup were not run. These are separate maintenance items, not unexecuted schema/data migrations. No test email, group access mail, credential generation or retry of historical mail failures was performed.

## Preservation and runtime verification

Strict per-record digest comparison preserves all original records in the checked datasets:

| Dataset | Preserved original count |
| --- | ---: |
| Normal user identities/password fields | 4,610 |
| Form responses / choices / options | 643 / 638 / 153 |
| Form questions / questionnaires | 63 / 75 |
| Meeting registrations | 6 |
| Proposals / comments | 284 / 26 |
| Assemblies / processes | 62 / 40 |
| Group memberships | 1 |
| Stored blobs / attachments | 1,421 / 1,170 |

There are no questionnaire Templates. Form table/foreign-key/question-field/type renames are normalized explicitly in the comparison. Header snippets and selectable organization languages match. All original content blocks keep IDs, scope, weight and publication except the three **unpublished** Metrics blocks removed by the native release migration. Hero/banner settings match the expected migrated values. Berlin's missing-hero fix preserves old CTA data in one new **unpublished** hero; no visible hero was added there.

All original storage metadata/checksum records remain unchanged. Current totals are 1,423 blobs and 1,178 attachments; extra records created during deployment/rendering do not replace originals. These metadata checks do not assert that every object-storage byte was downloaded. No upload was performed.

The new configuration exposes global upload defaults of 10/5 MB where the old version used organization-settings/secrets fallback methods. An independent read-only old/new runtime check confirms **identical effective attachment/avatar limits in all seven organizations**. SMTP's actual transport uses requested read_timeout **15 seconds**, open_timeout **5**, and preserved STARTTLS **false**. Other compared configuration, secret/SMTP credential/identity digests, header snippets and locale settings match.

## Public checks, logs and acceptance

All **53 configured language homepages across seven organizations** pass, along with compiled CSS/JS, API docs/read-only GraphQL, expected 404s, Berlin map/list/CSS bytes, Mitte link, assembly/process pages and taxonomy filtering. There are **94 anonymous HTTP checks**. The corrected Berlin page has separate level/district root parameters and unique filter DOM IDs. The map remains confined to Berlin and retains all thirteen map links plus the thirteen-item list. No new browser session or login/upload flow was used.

A bounded final sample of 3,000 web lines and 44 worker lines has zero completed HTTP 5xx, mail read timeouts or job-error markers. The pre-upgrade **190** failed MailDeliveryJob/Net::ReadTimeout records are unchanged and were not retried. There are zero active jobs. This sample is not a mail-delivery guarantee. Existing base-image scanner findings remain the separately documented baseline, not resolved by this application upgrade.

The old maintenance pod is removed and the owned synthetic PostgreSQL test service is stopped. Original application checkout and unrelated repositories are untouched. Alex already accepted staging login/uploads; **production login/upload acceptance remains Alex's check**.

Private operational evidence is `.upgrade-backups/emvi0319-production-20261126/`: both backup status records, before/post-taxonomy/after-migration/final digests and configuration, all section reports, rollback evidence, migration log, partition test/result/final layout, release-task report, image/Helm checks, public checks and log summary. Scripts used are copied there with private permissions. Contact data remains only in the earlier approved preparation export.
