# Berlin district map

The 0.30.9 HTML-block sanitization backport strips style, script, SVG and dialog tags from the old Berlin homepage block. CSS then appears as text and the map disappears. Keep the upstream sanitizer in place. The replacement is a dedicated `berlin_district_map` content block, with reviewed static SVG/list templates and local, versioned CSS.

## Isolation and translated content

Only the organization with stored host `www.berlinmitallengestalten.de` can create/use the block. The admin homepage menu hides it elsewhere, the create command rejects other organizations, and rendering checks both the current organization and block owner. No database ID is hard-coded. Other organizations' existing HTML cells and sanitizer remain unchanged. Public static files can be requested directly, but only the Berlin block includes their URLs in a page. The current template loads `map-v2.css`. Increase the CSS filename and its template reference when changing asset content to avoid stale browser caches. Original v1 CSS/JS files remain available for cached pages, but the current block no longer includes the JavaScript.

Heading and introduction remain translated settings editable in the normal block editor. The conversion copies all eight nonempty existing locales: de, en, es, fr, pl, ar-SA, fa-IR and tr-TR. Heading text is escaped; introduction HTML retains standard admin sanitization. The eight source variants have identical CSS, JavaScript, SVG and link-list structure. Only the reviewed map/list markup is checked into the repository; the full production export and conversion backups stay private.

Desktop/tablet uses the existing 13 native SVG links (12 districts and the state council). The list is visible at every screen width: below the map on desktop/tablet, and on its own on mobile. Links work without JavaScript, and district labels stay visible during hover/focus. The old mobile dialog was redundant because the small-screen layout uses links directly; its broken handler with an undefined `viewportWidth` is not retained. CSS selectors are confined to `#berlin-district-map`; keyboard focus stays visible and motion honors reduced-motion preferences. Existing organization header snippets are not changed.

## Rollout

Publishing/merging/building this MR does not convert any block. There is no automatic database migration or deploy hook. First build and inspect the MR image, deploy to staging and verify ordinary tenant rendering. Staging currently has only the Graz organization; that does not validate the Berlin-specific component. The local synthetic fixture renders a Berlin organization under its exact host. A real staging acceptance of the component requires a separately prepared Berlin test tenant; do not rename the Graz tenant or import customer data as an implicit deployment step.

After acceptance and an authorized production conversion, use context `kubernetes-admin@cluster1`, namespace `decidim-emvi-production`, deployment `production`. The inspected Berlin HTML block ID is **63**; recheck it before applying. The task also checks the owning organization and homepage scope, so a wrong ID aborts. It retains the same block ID, weight and publication timestamp.

Preview only:

```sh
kubectl --context kubernetes-admin@cluster1 --namespace decidim-emvi-production \
  exec deployment/production -- env BLOCK_ID=63 \
  bundle exec rails emvi:berlin_map:convert
```

The conversion fingerprints every original locale's non-text structure and technical markup. If someone has changed it since inspection, it aborts for another review. Title/intro edits are preserved. Empty locales are skipped; additional nonempty locales require review. An already-converted block aborts without writing. Do not use a force flag or relax the fingerprint to get around a mismatch.

To apply, use the same command with `APPLY=1 BACKUP_PATH=/tmp/berlin-map-backup-YYYYMMDD-HHMMSS.json` after `env`. The task exclusively creates a mode-0600 backup, flushes it before changing the block, and uses a database transaction/row lock. An existing backup filename aborts without overwriting it. The backup contains the original settings and identifying metadata, plus a digest of the replacement. This is not a substitute for normal database recovery coverage.

Immediately copy the backup outside the ephemeral pod to a private local backup directory. Resolve the actual pod explicitly before `kubectl cp`; never put the JSON in Git, public storage or a public directory. Preserve that backup when rolling deployments. If conversion fails after creating a backup, inspect whether the transaction committed before retrying with a new filename.

Verify all eight translations, desktop/tablet/mobile links, keyboard focus, browser console/network and another organization. Do not test login or uploads; Alex handles those. The native map paths retain their existing assembly URLs, including the mixed-case Treptow path.

## Rollback

Keep the new application code deployed while restoring the block. Upload the private backup to that pod, then preview with:

```sh
kubectl --context kubernetes-admin@cluster1 --namespace decidim-emvi-production \
  exec deployment/production -- env BACKUP_PATH=/tmp/berlin-map-backup-YYYYMMDD-HHMMSS.json \
  bundle exec rails emvi:berlin_map:restore
```

Add `APPLY=1` to execute. Restore verifies the host, owner, scope, current manifest, converted-settings digest, weight and publication timestamp. It refuses to overwrite later editorial changes. Only original manifest/settings are restored; position/publication are untouched. Restoring the old HTML does **not** repair its rendering under 0.30.9: the sanitizer still strips its custom markup. This is an exact content rollback, not an application downgrade. Never remove the registered manifest from code while converted records still exist.

## Persistent labels and district list

Alex requested that district names stay visible while hovering and that the list appear below the map. The original pasted HTML contains the same 12 district links and state-council link retained in the component, but its media query hides the list above 47.9rem. The v2 stylesheet removes that desktop hiding rule. The component no longer includes the v1 JavaScript that hid matching labels on mouseenter. Native SVG link hover highlighting and keyboard focus remain CSS-only. Existing converted blocks pick up these changes on the next application deployment; no conversion or database change is required.

Verified locally: 8 tests / 127 assertions passed. At desktop width 1280, the Mitte path had its hover fill while its label remained visible, and the district list was displayed below the map. At mobile width 390, all 13 list links were displayed with no horizontal overflow. The preview browser reported no script errors. Production was not changed for this follow-up.

## Validation

Use Ruby 3.3.12 and the application bundle. The verification script only accepts Rails test mode and the isolated `emvi_030_data_rehearsal` PostgreSQL fixture. It runs inside transactions and sends no mail. A private, authorized block export in the shape `{ "content": { "de": "...", ... } }` is required; it is intentionally not committed.

```sh
DECIDIM_AVAILABLE_LOCALES='bs,ca,cs,de,en,es,fr,hr,it,nl,pl,pt,ro,ru,el,sl,sr-CS,tr-TR,ar-SA,fa-IR,uk,zh-TW' \
BERLIN_LEGACY_FIXTURE=/private/path/berlin-block.json \
DISABLE_SPRING=1 RAILS_ENV=test SENTRY_DSN='' AWS_EC2_METADATA_DISABLED=true \
AWS_REGION=eu-central-1 AWS_ACCESS_KEY_ID=local-test AWS_SECRET_ACCESS_KEY=local-test \
STORAGE_PROVIDER=local \
DATABASE_URL='postgresql://decidim_upgrade@/emvi_030_data_rehearsal?host=/private/tmp/decidim-0297-pg/socket&port=55439' \
bundle exec rails runner script/verify_berlin_map.rb
```

Tests cover all eight rendered languages and native link sets, cross-organization exclusion, admin menu/create restrictions, user-text sanitization, original settings/position/publication preservation, preview without writes, exact rollback, later-edit refusal, changed-source refusal and exclusive private backup creation. Set `BERLIN_MAP_PREVIEW_DIR` to generate a standalone local HTML/CSS/JS preview during the same checks. The fixture server started for the checks is stopped afterward.

Verified on 2026-10-17: **8 tests, 119 assertions, zero failures/errors** against the isolated fixture; production-mode Zeitwerk eager loading passed, JavaScript syntax passed, and `git diff --check` passed. A standalone browser preview at desktop width 1280 and mobile width 390 confirmed map/list switching, no mobile horizontal overflow, correct local navigation target, initialized enhancement without console errors, and keyboard focus on a map link with a 3px stroke. This preview uses minimal surrounding CSS and does not establish acceptance in the full deployed EMVI layout. No live conversion, login or upload was performed.
