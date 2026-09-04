# In-app announcement for Aaavatar 1.x users — "Aaavatar 2.0 is here"

Create this as an **Announcement** in avatar-admin (Payload). Publish it
**after** the 2.0.0 release is `latest` on GitHub (runbook step 9): the CTA
uses the `latest` download URL. Requires `backend/sql/021` applied and the
admin deployed with the `maxAppVersion` field (both part of the 2.0.0 `main`
push) — otherwise the field is missing and 2.0 installs would see the notice.

| Field | Value |
|---|---|
| Title | `Aaavatar 2.0 is here` |
| Slug | `aaavatar-2-0-launch` |
| Image | none |
| Primary CTA label | `Download Aaavatar 2.0` |
| Primary CTA URL | `https://github.com/Square-One-Official/Avatar/releases/latest/download/Aaavatar.dmg` |
| Frequency | Show once, ever |
| Audience | All users |
| Min app version | empty |
| **Max app version** | `1.99` (1.x installs only — v1 sends no version header and passes; 2.0 sends `2.0.0` and is excluded) |
| Published at | empty until go-live, then "now" |
| Newsletter | off (separate decision) |

Body (rich text; inline styling only — the macOS client renders it as Markdown):

> A new Aaavatar, built from the ground up: a fresh design, a real editor, background removal on your Mac, effects, and one-click sharing for LinkedIn, Slack and e-mail.
>
> **Before you install:** export a backup here first (Settings → Library back-up → Export library…). The new version has the same app name, so it replaces this one in Applications.
>
> Then, in the new Aaavatar, open Settings → Preferences → Import from Aaavatar 1 and pick that backup. Your cutouts, names and dates come along.

Verification after publishing: sign in on an Aaavatar 1.x install → the sheet
appears once; on a 2.0 install `GET /v1/announcements/pending` returns
`{"announcement": null}` for this slug.
