# EMVI locale cleanup for 0.30.9

Prepared on 2026-10-17 on `cleanup/emvi-locales-0.30`, based on merged upgrade main `3aa32dcb`. This is a separate change for review and a second staging deployment. It does not deploy or change production data.

## Scope and source comparison

Lustenau MR !89 removes the count placeholder from highlighted meeting/result links. EMVI already contained all 28 fixes, so there is no need to cherry-pick it. Lustenau MR !90 is a useful method, but its resulting files must not replace EMVI's: the original trees differ in 352 values/keys across 54 files, and 182 entries removed for Lustenau have different values in EMVI. The Polish terms override exists only in EMVI.

The cleanup compares EMVI's own YAML leaves with the official framework tags v0.27.0, v0.27.1 and v0.27.2. Only identical strings are removed. Regional codes may match their actual base-language fallback, such as ar-SA -> ar, tr-TR -> tr and sr-CS -> sr. Runtime staging fallback chains confirmed those relationships. Bosnian and Serbian are not compared with Croatian. Other custom values and YAML types remain intact.

This removes **48,396 copied strings** across 225 changed files; **82 files become empty and are deleted**. Texts under `emvi.*`, custom elected-member terminology and the Polish terms interpolation correction are preserved. Six applicable German wording corrections from !90 are included; “Über diese Organisation” was already correct. The remaining files use normal Psych formatting with quotes only where the serializer needs them, not all-value double quoting. Every rewritten file is checked for typed YAML roundtrip equality.

## Reviewed 0.30 interpolation repairs

`zz.emvi_030_compatibility.yml` holds **116 targeted overrides in 17 languages**, including repairs to outdated upstream translations that reappear after removing the copied files. The `zz` filename loads them after the old application locale files. The full configured set of 22 EMVI languages is used during testing; it must be set before Rails boot so lazy-loaded regional translations are actually included.

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

The locale suite passed **7 tests and 102,428 assertions**. It independently checks deleted values against the historical tags, remaining custom values against the pre-cleanup commit, YAML type preservation, important EMVI/Polish text, and real 0.30 interpolation bindings in all 22 languages. A second repair-generator run proposes zero corrections. The existing synthetic upgrade suite also passed again: 9 tests, 81 assertions, including public rendering, taxonomies and group authorship. The isolated PostgreSQL server was stopped afterward; no live data was used.

After the MR build/scans pass, merge for another staging deployment. Verify visible labels and actual affected features in the enabled tenant languages, especially bs, hr, sr-CS, tr-TR, ar-SA, fa-IR, el, sl, uk and Polish. Login and upload testing remains with Alex. This preparation sends no notifications and performs no browser login or upload. No schema migration is added by this MR.
