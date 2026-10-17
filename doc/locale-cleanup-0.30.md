# EMVI locale cleanup for 0.30.9

Prepared on 2026-10-17 on `cleanup/emvi-locales-0.30`, based on merged upgrade main `3aa32dcb`. This is a separate change for review and a second staging deployment. It does not deploy or change production data.

## Scope and source comparison

Lustenau MR !89 removes the count placeholder from highlighted meeting/result links. EMVI already contained all 28 fixes, so there is no need to cherry-pick it. Lustenau MR !90 is a useful method, but its resulting files must not replace EMVI's: the original trees differ in 352 values/keys across 54 files, and 182 entries removed for Lustenau have different values in EMVI. The Polish terms override exists only in EMVI.

The cleanup compares EMVI's own YAML leaves with the official framework tags v0.27.0, v0.27.1 and v0.27.2. Only identical strings are removed. Regional codes may match their actual base-language fallback, such as ar-SA -> ar, tr-TR -> tr and sr-CS -> sr. Runtime staging fallback chains confirmed those relationships. Bosnian and Serbian are not compared with Croatian. Other custom values and YAML types remain intact.

This removes **48,396 copied strings** across 225 changed files; **82 files become empty and are deleted**. Texts under `emvi.*`, custom elected-member terminology and the Polish terms interpolation correction are preserved. Six applicable German wording corrections from !90 are included; “Über diese Organisation” was already correct. The remaining files use normal Psych formatting with quotes only where the serializer needs them, not all-value double quoting. Every rewritten file is checked for typed YAML roundtrip equality.

## Reviewed 0.30 interpolation repairs

`zz.emvi_030_compatibility.yml` holds **125 targeted overrides in 18 languages**, including repairs to outdated upstream translations that reappear after removing the copied files. The `zz` filename loads them after the old application locale files. The full configured set of 22 EMVI languages is used during testing; it must be set before Rails boot so lazy-loaded regional translations are actually included.

The reviewed call contracts cover:

- Highlighted meeting/result/proposal links and the new-debate action without old count/name parameters.
- Debate notifications using participatory-space title/URL parameters.
- Bulk budget selection using `successful` / `errored`, rather than `projects`.
- Generic import notices using `count`, proposal-import success without the removed number argument, and sortitions using taxonomy labels.
- Meeting confirmation with `title` / `url`, and reminder subjects with a meeting title. Reminder subjects reuse the existing localized close-meeting label.
- The comments onboarding link receiving plain text, without nested legacy sign-in/sign-up anchors.
- Color-contrast warnings retaining the same fixed WebAIM destination formerly supplied by the 0.27 view.

This is not a blanket English-placeholder replacement. The source still supplies extra parameters such as search `collection`, log `space_name`, event `resource_path` / `author_path` and pluralization `count`; these translations are preserved. Obsolete unused keys are not broadly deleted. The small amount of new success wording and the shortened meeting-reminder subjects should receive normal language review; interpolation tests do not establish native-speaker quality.

## Validation and repeatability

Run with Ruby 3.3.12, the installed application bundle and an upstream framework checkout containing the official tags. The default sibling checkout is `../decidim`; `--upstream PATH` or `UPSTREAM_DECIDIM_CHECKOUT` selects another location.

```sh
# Read-only report; add --write to apply exact-stock removals.
bundle exec ruby script/cleanup_legacy_locales.rb
```

The script protects the explicit Polish and 0.30 compatibility files. A second cleanup run proposes zero deletions or changes.

Use the full production locale list for Rails checks. Dummy AWS/storage/database settings can be used; these scripts do not access a database or send mail:

```sh
export DECIDIM_AVAILABLE_LOCALES='bs,ca,cs,de,en,es,fr,hr,it,nl,pl,pt,ro,ru,el,sl,sr-CS,tr-TR,ar-SA,fa-IR,uk,zh-TW'
bundle exec rails runner script/verify_locale_cleanup.rb
# Read-only compatibility audit. WRITE_LOCALE_FIXES=1 persists reviewed repairs.
bundle exec rails runner script/fix_locale_interpolations.rb
```

The locale suite passed **9 tests and 102,444 assertions**. It independently checks deleted values against the historical tags, remaining custom values against the pre-cleanup commit, YAML type preservation, important EMVI/Polish text, and real 0.30 interpolation bindings in all 22 languages. A second repair-generator run proposes zero corrections. The existing synthetic upgrade suite also passed again: 9 tests, 81 assertions, including public rendering, taxonomies and group authorship. The isolated PostgreSQL server was stopped afterward; no live data was used.

After the MR build/scans pass, merge for another staging deployment. Verify visible labels and actual affected features in the enabled tenant languages, especially bs, hr, sr-CS, tr-TR, ar-SA, fa-IR, el, sl, uk and Polish. Login and upload testing remains with Alex. This preparation sends no notifications and performs no browser login or upload. No schema migration is added by this MR.

## German statistics heading follow-up

After MR !260 was merged, staging exposed a wrong-language upstream translation: Decidim 0.30.9 ships `Starea curentă a %{organization}` under `de.decidim.pages.home.statistics.headline`. The identical old German stock entry had previously masked this upstream defect and was removed during cleanup. Interpolation checks alone did not detect the Romanian wording.

A targeted application override restores the previous `Aktueller Zustand von %{organization}` wording. The repair generator now reproduces this exception and a runtime regression assertion checks the exact German heading with the organization name (`Aktueller Zustand von graz`). No staging configuration or organization language setting is changed.

## Regional Arabic fallback and CI component follow-up

The Arabic menu entry used `locale.name` in `ar-SA`, but displayed English. Upstream `ar-SA.yml` declares its translations under `ar`; the application's I18n available-locales list included only selectable Decidim locale codes. I18n 1.15.2 silently discards unavailable translation roots in `store_translations`, so the `ar-SA -> ar -> en` fallback chain could not use Arabic even though it listed `ar`.

The I18n loader now admits base languages for all configured regional codes. `Decidim.available_locales` and organization language menus remain unchanged; no extra selectable languages or database settings are added. The language-chooser helper now returns `العربية` for `ar-SA`. A regression checks that exact helper result, parent availability, an actual Arabic homepage translation and the unchanged Decidim language catalog.

Loading the Arabic source also exposes eight known 0.30 interpolation mismatches previously masked by English fallback. The existing reviewed repair generator covers them: new-debate action, comment onboarding, proposal import, sortition labels and four debate notifications. Their overrides are included, with an Arabic proposal-import success message. The compatibility file now contains 125 overrides across 18 locales.

At Alex's request, `.gitlab-ci.yml` now includes `gitlab.webface.at/components/rails-deploy/pipeline@buildkit`, following the branch instead of commit `4407075d811337c775f4512d696d50cdcd7aade5`. Ruby/Node versions and the other inputs are unchanged. GitLab CI lint accepted the branch-based configuration without errors or warnings. This note supersedes the historical commit-pin description in the original upgrade preparation.

The regional-fallback follow-up passed **9 locale tests / 102,444 assertions**, and the repair generator proposes zero further changes. No live deployment, login or upload test was performed for this follow-up.
