# EMVI 0.30.9 staging observation

Checked on 2026-10-17 in context `kubernetes-admin@cluster1`, namespace `decidim-emvi-staging`. Alex explicitly waived a new staging backup. No backup was created in this step.

Pipeline 6797 completed build 27112 and staging job 27113 successfully. Its manual production rollout jobs remain untouched. The running web and GoodJob image is `gitlab.webface.at:5050/mitgestalten/decidim-emvi/main:3aa32dcb21f9043488fe7d1def91b26f592b455c`. Both application containers are ready with zero restarts. The migration pod succeeded; Rails independently reports Decidim 0.30.9, Ruby 3.3.12 and no pending schema migrations. No Kubernetes warning events were present.

The 29 PaperTrail jobs were scheduled for 15:20:49 Europe/Vienna. By 15:22:45 all 29 had finished without errors, and no legacy `old_object_changes` values remained. There were no new failed jobs since deployment. The sampled web/worker logs showed no HTTP 500 completions or worker exceptions.

The configured organization host is `emvi-staging-graz.participation.works`. Read-only HTTP checks returned 200 for its homepage and `/api/docs`, and a rendered 404 for an unknown path with translation toggling enabled. `/processes` and `/assemblies` return 404; both corresponding published-space counts are zero. The generic `emvi-staging.participation.works` host has no organization and redirects to `/system/`. These results do not verify any authenticated application flow.

No login, upload or mail-delivery test was performed. Production was not changed. Staging has no categories, scopes, areas, uppercase user nicknames, deleted user accounts, private exports or old unattached blobs in the inspected counts.

## Completed release tasks

Alex explicitly authorized the twelve one-time tasks on 2026-10-17 after the earlier approval-review rejection. They all completed successfully at 16:55 Europe/Vienna. The user’s staging-backup waiver remained in effect.

Preflight guards confirmed no categories/scopes/areas, deleted accounts, private exports or their attachments, private participatory spaces, or unattached blobs older than one hour. The generated plan for the sole organization contained no imported taxonomies and was reviewed before import. All five importer sections reported zero failed resources/components and created no taxonomies or filters. Metrics conversion and proposal-category updates completed. Nickname correction changed zero users; action-log correction found zero records. Deleted-user, export, private-follow and attachment cleanup tasks completed without candidates.

The full execution log and the empty plan/result JSON are preserved outside the ephemeral pod at `/private/tmp/emvi-030-staging-tasks.log` and `/private/tmp/emvi-030-staging-taxonomy-plans-results.json`. These are local operational evidence, not repository artifacts. Production still needs its separate backup, reviewed nonempty taxonomy plans and release tasks.

The locale cleanup is a separate MR based on the deployed main revision. Its local checks are recorded in `locale-cleanup-0.30.md`; its results are not yet deployed or tested on staging.
