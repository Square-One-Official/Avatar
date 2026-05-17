# Data Protection Impact Assessment — Cloud AI Image Processing

_GDPR Art. 35. Controller: Square One (Netherlands). Author: Thierry
Emmery. First issued: 2026-05-18. Review cadence: annually + on any
change to the processing chain._

## 1. Why a DPIA

GDPR Art. 35 requires a DPIA when processing is **likely to result in
high risk** to data subjects. Avatar's cloud AI features (Magic Cutout,
Colorize, Fill in Body) submit user-supplied portrait photographs — a
special category of personal data when biometric identifiers are
involved — to a US-based AI inference provider (Replicate). That
triggers Art. 35(3)(b) (large-scale processing of special-category
data) at the upper bound and Art. 35(1) (international transfer + new
technology) at the lower bound. Either way, we assess.

## 2. Description of the processing

### 2.1 Nature

Three feature paths, each user-triggered and per-image:

| Feature | What it sends | What comes back | Replicate model |
|---|---|---|---|
| **Magic Cutout** | Original portrait PNG | Transparent-background PNG (alpha matte) | `men1scus/birefnet` (BiRefNet) |
| **Colorize** | RGBA cutout, flattened to RGB over neutral grey | Colorized RGB photo | `arielreplicate/deoldify_image` (DeOldify) |
| **Fill in Body** | Padded RGB canvas + binary mask | Outpainted RGB photo | `black-forest-labs/flux-fill-pro` |

The image lives on Supabase Storage briefly (5-minute signed URL),
Replicate fetches it directly, returns a result URL we download and
re-encode for the client.

### 2.2 Scope

- **Categories of data**: a single photograph per request. The
  photograph may contain biometric features (face, head shape). The
  photograph is **not** annotated with identifying metadata by the
  app — EXIF is stripped before upload via the `sharp` pipeline.
- **Volume**: one inference per user-initiated cutout / colorize /
  fill-body call. Per the audit, default rate limit is 3 cutouts per
  6 seconds per user; max sustained ~30 / minute.
- **Retention by Replicate**: per Replicate's
  [privacy policy](https://replicate.com/privacy), prediction inputs
  and outputs are retained only for the request lifetime + a short
  diagnostic window (typically minutes). Replicate does NOT use
  prediction data for model training under their default account
  settings.

### 2.3 Context

- The user explicitly triggers each call (button press in the macOS
  app). The request is the consent signal.
- The app surfaces these features only when
  `PrivacyPreferences.mode == .cloudAllowed`; the Local-only mode
  disables them entirely.
- Pro feature gating + credit ledger ensures abuse is rate-capped by
  cost.

### 2.4 Purposes

To deliver the feature the user just clicked. No secondary use:

- Not used for analytics.
- Not used to train any model controlled by Square One.
- Not used to enrich any user profile beyond the immediate response.

## 3. Necessity & proportionality

- **Necessity**: cloud inference is the only way to deliver
  BiRefNet-quality matting and Flux outpainting on a consumer Mac
  without bundling a multi-GB model file. The local Subject Lift V2
  fallback exists for users who don't want cloud processing.
- **Data minimization**: we send a single image per call, nothing else
  (no user ID, no metadata). Replicate sees the image and the model's
  parameters only.
- **Anonymity**: from Replicate's perspective, the caller is the
  Square One Replicate account. End-user identity is never sent.
- **Retention**: image bytes leave our infrastructure as soon as
  Supabase Storage's signed-URL window expires (5 min) and the
  best-effort cleanup in `/v1/cutout` succeeds. Right-to-erasure
  (`DELETE /v1/account`) sweeps any residue.

## 4. Risk assessment

### Risk matrix

| Risk | Likelihood | Severity | Mitigation |
|---|---|---|---|
| **Replicate logs the image** | Low | High | Vendor contract (DPA + Replicate's own policy) prohibits training on data. Replicate's diagnostic-window logs are short-lived. We can opt into "Private mode" via Replicate's account settings if needed. |
| **Image intercepted in transit** | Very low | High | TLS pinning on `api.aaavatar.nl` (audit CRITICAL #4); Supabase + Replicate force TLS 1.2+. ATS strict-mode on macOS. |
| **Signed URL leaked** | Low | Medium | 5-minute TTL; storage key validated against `userId/` prefix; signed URLs no longer logged (audit MEDIUM #21). |
| **Model output misused** | Low | Low | Output goes back to the originating user only. Not stored server-side. |
| **Vendor change** | Medium | Medium | Replicate is a single point of failure. Migration path: swap the `MODEL_VERSION` constants in `backend/lib/replicate.ts`; same image-input contract works with any of the alternatives (Replicate, fal.ai, RunPod). |

### Special-category data assessment

Photographs of a face are **only** considered biometric data when
processed *for the purpose of uniquely identifying a person* (GDPR
Art. 9(1)). The three Replicate features here do background removal,
colorization, or outpainting — none performs identification or
matching. We process the image as ordinary personal data, not Art. 9
biometric data.

If a future feature DID identify (e.g., face-clustering across the
user's library), this DPIA must be re-issued with explicit consent
collection + opt-in.

## 5. Safeguards

- **Encryption at rest** — Supabase Storage AES-256.
- **Encryption in transit** — TLS 1.2+ everywhere, certificate pinning
  on the macOS client.
- **Access controls** — Storage bucket policy restricts read to signed
  URLs only; uploads scoped to per-user prefix.
- **Logging** — signed URLs and storage keys are redacted before
  logging.
- **Right to erasure** — `DELETE /v1/account` purges storage prefix +
  all derived rows.
- **Data residency** — Supabase Postgres + Storage in `eu-central-1`.
  Replicate is US — covered by the Replicate DPA as an Art. 44 transfer
  with appropriate safeguards (Standard Contractual Clauses).
- **Local-only mode** — the user can opt out of cloud AI entirely;
  Subject Lift V2 runs on-device.

## 6. Consultation

- **Users**: the privacy policy at
  [`website/privacy.md`](../../website/privacy.md) discloses cloud AI
  features, the Replicate (US) transfer, and the local-only opt-out.
- **DPO**: Square One is below the GDPR Art. 37 threshold for a
  designated DPO. Thierry is the standing privacy contact.
- **Autoriteit Persoonsgegevens** (NL DPA): no prior consultation
  required — the residual risk after mitigations is **low** (table § 4
  shows no Low-likelihood × High-severity row remaining after
  mitigations).

## 7. Conclusion

Residual risk is **low**. The processing is necessary, proportionate,
and adequately safeguarded. This DPIA can stand for one year subject to
the change triggers in § 8.

## 8. Change triggers (re-issue this DPIA when any of these happen)

- New cloud AI feature added.
- Replicate replaced or augmented by another inference provider.
- Replicate's privacy policy or model-training stance changes
  materially.
- Local-only opt-out removed.
- A feature introduced that identifies, matches, or clusters faces
  (Art. 9(1) trigger).
- Data residency of the upstream provider changes outside the EU/US
  Standard Contractual Clauses framework.

## 9. Revision history

| Date | Author | Change |
|---|---|---|
| 2026-05-18 | Thierry | Initial issue — covers Magic Cutout, Colorize, Fill in Body. |
