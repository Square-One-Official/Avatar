# Aaavatar 2.0 — launch comms (small, personal, over a few days)

Owner: Thierry. Audience: anyone helping with marketing. Tone: down to earth,
first person, no "we're thrilled to announce". One idea per post.

## The line

> Aaavatar now has folders and effects.
> One consistent look for every team portrait photo: aaavatar.nl

Keep it. It says what changed and what the product is for. Optional second
sentence when a post needs more: "Drop in a photo, pick a background, share
it in the right size for LinkedIn, Slack or e-mail."

## What is true today (safe to claim)

| Claim | Basis |
|---|---|
| Folders for sets of portraits, batch actions | Library/board, 2.0 |
| Effects: Balloon, Windy, Sticker, Flowers, 3D Head, Hairy (6 live) | `/v1/effects` on 2026-09-04 |
| Background removal happens on your Mac, nothing is uploaded for it | On-device Vision/ORMBG |
| One-click share sizes for LinkedIn, Slack, e-mail | Share sheet |
| Free to start; cloud edits (Fill in body, Boost resolution, AI background, effects) use credits, Pro and top-ups in Settings → Billing | Billing |
| Requires **macOS 14** (Sonoma) or newer | Info.plist |
| Sign in with e-mail, one-time code, no password | Auth 2.0 |

Do not claim: face retouching (out of scope), banners (feature flag off),
"AI headshot generator" (the FAQ explicitly says it is not one), Windows/iOS,
specific credit maths (show the tiles, never per-credit prices).

## Two things the site must say before you push traffic

1. **"macOS 13+" on aaavatar.nl is wrong for 2.0** — change to macOS 14+.
2. Check the pricing section against what Settings → Billing actually shows
   (plans and top-ups); the draft copy still has a Free/Pro split from June.

## Existing users (this is the part to get right)

2.0 has the same app name as 1.x and replaces it when dragged into
Applications. Anyone on 1.x must **export a backup first**
(Settings → Library back-up → Export library…), then import it in the new
version (Settings → Preferences → Import from Aaavatar 1).

- In-app: the Announcement in avatar-admin (spec in `ANNOUNCEMENT-2.0.0.md`)
  reaches 1.x installs only. Publish it first.
- On social: pin one reply under every launch post:
  "Already using Aaavatar? Export a backup in the old version first
  (Settings → Library back-up). 2.0 replaces it, then import the backup."
- E-mail to existing accounts: possible from the same Announcement
  (newsletter toggle). This counts as a product update to account holders,
  not marketing; the double-opt-in filter decision (DECISIONS-PENDING) is only
  needed before a pure marketing send.

## Channels and a light cadence

**Day 0**
- LinkedIn (personal): the line + the video. First three seconds of the video
  should show a before/after or the folder view, not a logo.
- X: same line, video attached natively, link in a reply if the algorithm
  punishes links.
- Product Hunt: post a maker update on the existing page ("2.0: folders,
  effects, on-device background removal") with the video. A full re-launch
  costs a full day of replying; only do that later, deliberately, with the
  video ready and a free-plan angle.

**Days 1 to 7, one post each, alternate LinkedIn and X**
1. Folders: a team set, before and after, "same look for the whole team".
2. Effects: two examples side by side (Sticker and 3D Head read best small).
3. Privacy: "background removal runs on your Mac, the photo never leaves it".
4. Share sizes: LinkedIn, Slack, e-mail from one portrait.
5. Coming from 1.x: the backup line, as its own post.
6. A short "how I made this" with the video's raw footage, no polish.

## Assets to prepare once

- The video (also cut a 15 s version for X and PH).
- Three screenshots: folder grid, effects panel with two effects applied, share sheet.
- Link only to aaavatar.nl. Never link the GitHub release directly; the site
  link always serves the newest version.

## Replies you will need

- "Is this AI-generated?" — No. It is your photo with a consistent frame and
  background; effects are optional and clearly styled.
- "Windows?" — Mac only, macOS 14 or newer.
- "Price?" — Free to start; cloud edits use credits, Pro and top-ups in the app.
- "What about my old library?" — Export a backup in the old version, import it
  in 2.0. The old version stays downloadable from the release page.
