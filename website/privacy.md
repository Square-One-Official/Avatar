# Privacy Policy

_Last updated: 17 May 2026_

Avatar (also branded as Aaavatar) is a macOS application published by **Square One** (the Netherlands, info@squareone.nl). This Privacy Policy explains what data Avatar handles, how it is used, and the rights you have. It applies to the Avatar macOS app, the website [https://aaavatar.nl](https://aaavatar.nl), and the back-end services at `api.aaavatar.nl` and `admin.aaavatar.nl` that support Avatar's Pro features.

If you have any questions, contact us at **info@squareone.nl**.

---

## 1. Summary

Avatar is **local-first** for the things that matter — your portraits, your edits, and your library all live on your Mac. Image processing for Subject Lift V2 runs entirely on-device.

For optional features Square One does operate cloud services:

- **Pro subscription + credits** — payment processing through Stripe and an account record in our database so the app can verify your subscription state and Magic Cutout credit balance.
- **Magic Cutout / Colorize / Fill-Body** — the source photo for these AI features is sent to our backend, which forwards it to Replicate.com for inference and returns the result.
- **Newsletter** — if your account is opted in, occasional product announcements are sent through Resend.
- **Shared Google Drive workspaces** — when you opt in, your portraits sync through your own Google Drive; nothing passes through Square One on that path.

Whenever this policy says "we" it means Square One (Netherlands). For Avatar's purposes Square One is the **data controller** under GDPR; the third parties listed in [§ 6](#6-third-parties-and-subprocessors) are **processors** acting on our instructions.

---

## 2. Data Avatar handles

### 2.1 On your Mac

Avatar stores the following locally on your device, using Apple's SwiftData framework:

- Portrait images you import (originals and AI-generated cutouts)
- Background images and presets
- Export presets
- App preferences (language, last-opened workspace, UI state)

This data never leaves your Mac unless you explicitly enable a Google Drive workspace or export a library archive yourself.

### 2.2 In your Google Drive (optional)

When you create or join a shared workspace, Avatar uses the Google Drive API to store the following **inside a folder you own in your own Google Drive**:

- A folder named `Avatar Workspace - <name>` at a location you choose
- A `workspace.json` file with the workspace name, creation date, and creator email
- Portrait packages (`.avatarportrait`) and background packages (`.avatarbg`) inside `portraits/` and `backgrounds/` subfolders
- Permissions you grant to collaborators through Avatar's invite flow

We never receive a copy of any of this data. It lives exclusively in your and your collaborators' Google Drives.

### 2.3 Automatic updates

Avatar checks for application updates through the [Sparkle](https://sparkle-project.org/) framework by fetching an appcast file from GitHub. Your IP address and basic HTTP metadata may be logged by GitHub when this check happens. We do not receive that data.

---

## 3. How Avatar uses Google user data

Avatar requests the following Google OAuth scope:

- `https://www.googleapis.com/auth/drive` — read/write access to files in your Google Drive

This scope is used **only** to:

1. Create and manage the `Avatar Workspace - <name>` folders you explicitly create
2. Read and write portrait and background files inside those workspace folders
3. Detect workspace folders that other users have shared with the Google account you signed in with, so that shared workspaces appear in Avatar automatically
4. Send Google Drive sharing invitations on your behalf when you click **Invite** in Avatar
5. List, and at your request revoke, the access other people have to a workspace folder

Avatar does **not** read, modify, or index any other files in your Google Drive. Avatar does **not** upload your Google data to any server operated by Square One or any third party.

### 3.1 Google API Services User Data – Limited Use

Avatar's use and transfer of information received from Google APIs to any other app adheres to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the **Limited Use** requirements. In particular:

- We use Google user data only to provide user-facing features within Avatar.
- We do not use Google user data for serving advertisements.
- We do not allow humans to read the data except (a) with your explicit consent, (b) for security purposes such as investigating abuse, (c) to comply with applicable law, or (d) for internal operations where the data has been aggregated and anonymised.
- We do not transfer Google user data to third parties except as necessary to provide or improve user-facing features, comply with applicable law, or as part of a merger, acquisition, or sale of assets with user notice.

---

## 4. Local authentication data

When you sign in with Google, Avatar stores your OAuth access and refresh tokens in the macOS Keychain on your Mac, via Google's GoogleSignIn SDK. These tokens never leave your Mac. You can revoke them at any time by signing out inside Avatar or at [https://myaccount.google.com/permissions](https://myaccount.google.com/permissions).

---

## 5. Data retention and deletion

- **Local data** stays on your Mac for as long as you keep Avatar installed. Quitting Avatar and deleting its app container removes all local portraits, backgrounds, and preferences.
- **Drive data** stays in your Google Drive until you delete it. Removing a workspace folder from Drive removes all associated data.
- **Authentication tokens** are removed from the Keychain when you sign out inside Avatar.
- We do not keep backups of your Google data, because we never receive it.

To revoke Avatar's access to your Google account at any time, visit [https://myaccount.google.com/permissions](https://myaccount.google.com/permissions) and remove Avatar.

---

## 6. Third parties and subprocessors

Avatar uses the following third-party services. We disclose them as **subprocessors** under GDPR Art. 28; the live list is also maintained at [`docs/legal/subprocessors.md`](https://github.com/Square-One-Official/Avatar/blob/main/docs/legal/subprocessors.md) in the source repository.

| Service | Purpose | What it sees | Hosting region |
|---|---|---|---|
| **Supabase** (Supabase Inc., US — EU data residency on Pro plans) | Account database, authentication tokens, billing state, ledger of Magic Cutout credits, server-side state for shared workspaces | Your email, Avatar account ID, Stripe customer ID, subscription tier, credit balance | EU (eu-central-1) |
| **Stripe** (Stripe Payments Europe, Ireland) | Pro subscription checkout, payment, invoicing, customer portal | Your email, payment method, billing address, IP, country | EU + US |
| **Replicate** (Replicate Inc., US) | Inference for Magic Cutout, Colorize and Fill-Body — receives the source image you submit for that feature | The image you upload for the feature, for the duration of the request | US |
| **Resend** (Resend, Inc., US — EU sending region) | Sending product announcement emails to opted-in users | Your email and the rendered email contents | EU |
| **Vercel** (Vercel Inc., US — EU edge region) | Hosting for `api.aaavatar.nl` and `admin.aaavatar.nl` | Request logs (IP, timestamp, path) for the duration of standard log retention | EU (cdg1, fra1) |
| **Google Drive API** | Workspace storage & sharing | Your portraits, backgrounds, and workspace metadata (stored in your Drive) | Google global |
| **Google Sign-In** | Authentication for Google Drive workspaces | Your Google email, name, profile picture | Google global |
| **GitHub (appcast)** | Update checks | IP address, HTTP metadata | GitHub global |
| **Sparkle framework** | In-app updater | No data sent externally | n/a |

We do not use analytics, crash reporting, or advertising SDKs. Replicate retains uploaded images only as long as the inference request needs and does not use them for model training (per Replicate's [data policy](https://replicate.com/privacy)).

---

## 7. Children's privacy

Avatar is not directed at children under 13 and we do not knowingly collect information from them.

---

## 8. International users

Avatar is published from the Netherlands. By installing Avatar and signing in with Google, you acknowledge that authentication flows and Drive storage will involve Google's infrastructure, which may process data internationally under [Google's own terms](https://policies.google.com/privacy).

---

## 9. Legal bases for processing (GDPR Art. 6)

We rely on different legal bases depending on what Avatar is doing for you at the moment:

| Processing activity | Legal basis | Notes |
|---|---|---|
| Running Avatar locally on your Mac | n/a — no Square One processing | The app holds no personal data on our side. |
| Creating an Avatar account, signing you in | **Art. 6(1)(b) contract performance** | Necessary to deliver the Pro service you signed up for. |
| Processing your Pro subscription, invoicing, refunds | **Art. 6(1)(b) contract performance** | Through Stripe as a processor. |
| Magic Cutout / Colorize / Fill-Body inference | **Art. 6(1)(b) contract performance** | You explicitly request the operation for each photo; the request body itself is the consent signal. |
| Storing the per-account credit ledger and device-grant rows used for free-trial accounting | **Art. 6(1)(f) legitimate interest** in preventing trial abuse | The data minimised to what's needed to deny duplicate trials on the same Mac. |
| Sending product announcement emails to your account email | **Art. 6(1)(a) consent** | Opt-in only; every email carries a one-click unsubscribe link and we record opt-outs in our `newsletter-unsubscribes` collection. |
| Operational logs at `api.aaavatar.nl` (request path, IP, timestamp) | **Art. 6(1)(f) legitimate interest** in service reliability and security | Retained for the standard Vercel log window. |
| Google Drive workspace data | **Art. 6(1)(a) consent + Art. 6(1)(b) for the workspace itself** | Stored in *your* Drive; Square One never receives it. |

Withdrawing consent: for the newsletter, use the unsubscribe link in any email or write to news@aaavatar.nl. For Google Drive workspaces, sign out inside Avatar and revoke access at [https://myaccount.google.com/permissions](https://myaccount.google.com/permissions). Withdrawing consent for newsletter doesn't affect the lawfulness of past sends.

## 10. Your rights under the GDPR

If you are in the European Economic Area, you have the right to:

- **access** the personal data Square One holds about you (request via info@squareone.nl);
- **rectify** that data when it is wrong;
- **erase** your data — sign out inside Avatar to clear the local cache, and email info@squareone.nl to ask us to delete your account record + ledger entries from Supabase. We honour the request within 30 days; some records (invoices) are retained where Dutch tax law requires it (typically 7 years);
- **restrict** or **object** to processing based on legitimate interest;
- **port** your data to another service;
- **withdraw** any consent you previously gave, including for the newsletter;
- **lodge a complaint** with a supervisory authority, in the Netherlands the [Autoriteit Persoonsgegevens](https://autoriteitpersoonsgegevens.nl).

---

## 11. Changes to this policy

We may update this policy when the app changes or when legal requirements change. The date at the top of this page shows when it was last updated. Material changes will be highlighted in the Avatar release notes.

---

## 12. Contact

**Square One**
The Netherlands
**info@squareone.nl**

For data-protection questions, use the same email.
