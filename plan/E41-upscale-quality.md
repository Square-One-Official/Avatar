# E41 — Boost Resolution: beste model + lokale optie

Team: **INFRA** (cloud-model + endpoint-params) · **FEAT** (lokale on-device-route + wiring)

Voortgekomen uit een audit (Thierry, 2026-06-26): "gebruiken we het beste AI-model om een portret
te upscalen/verscherpen?" Bevinding: `/v1/upscale` draaide **Real-ESRGAN met `face_enhance:
false`** — een generieke upscaler met de gezicht-specifieke stap UIT, suboptimaal voor portretten.
Besluit: check Replicate, zet de winnaar als default, én bied een **lokale optie** voor wie online
modellen niet toestaat (`AIPrivacyMode2.localOnly`).

Replicate-research (2026-06-26): **philz1337x/crystal-upscaler** is portret-geoptimaliseerd —
behoudt huidtextuur + gezichtsidentiteit zonder "plastic look", tot 10K, snel (~1.2s @1K),
~$0.016/beeld. Wint voor een avatar-app (identiteit = het product; anti-AI-slop). Alternatieven:
sczhou/codeformer (goedkoop ~$0.0065, face-restore + fidelity-knop), topazlabs/image-upscale
(premium/veelzijdig), Real-ESRGAN+`face_enhance:true` (bijna gratis fallback). Bronnen in de
commit-/chat-historie.

---

## 41.1 — Cloud-default → crystal-upscaler + per-model input-adapter
- status: done (port-only; preview-verificatie + hash-pin open)
- owner: INFRA (2026-06-26)
- team: INFRA
- Result: `models.ts` `upscale.defaultModel` → `crystal-upscaler` (`philz1337x/crystal-upscaler`,
  portret-geoptimaliseerd), met `real-esrgan` als alternatief in de registry. `replicate.ts`:
  nieuwe `upscaleInputFor(ref, imageDataUrl)` (spiegelt `stylizeInputFor`) — crystal →
  `{ image, scale_factor: 2 }`, Real-ESRGAN/onbekend → `{ image, scale: 2, face_enhance: true }`
  (de audit-bevinding: face_enhance stond op false → nu aan voor de fallback). Swift-kant
  (`BackendClient.upscale`) ongewijzigd. **Open (alleen op deploy te doen):** crystal is een
  community-model → pin de versie-hash + verifieer `/v1/upscale` op een Vercel preview-deploy
  (`cd backend && vercel`); bij 404 hash herpinnen. Port-only → niet door build-v2.sh gedekt.

- `backend/lib/models.ts`: `upscale.defaultModel` → `crystal-upscaler`; voeg het model toe aan de
  registry (community-slug → **gepinde versie-hash vereist**, te bevestigen op de preview-deploy;
  net als birefnet/deoldify). Houd `real-esrgan` als alternatief in de registry, nu met
  `face_enhance: true`.
- `backend/lib/replicate.ts`: `upscale()` mag niet langer één vaste input-dict hardcoden — crystal
  gebruikt `{ image, scale_factor }`, Real-ESRGAN `{ image, scale, face_enhance }`. Introduceer
  `upscaleInputFor(modelRef, imageDataUrl)` (spiegelt `stylizeInputFor`).
- Port-only (niet door build-v2.sh gebouwd): verifieer endpoint + pin de crystal-versie-hash op
  een Vercel preview-deploy vóór productie.
- DoD: Swift-kant (BackendClient.upscale ongewijzigd) bouwt; backend port-only → preview-test;
  Result-regel.

## 41.2 — Lokale on-device Boost (localOnly, geen cloud/credits)
- status: done
- owner: FEAT (2026-06-26)
- team: FEAT
- Result: `LocalUpscale` (Core Image, gedeelde GPU-`CIContext`): Lanczos 2× + milde unsharp-mask op
  de cutout-PNG (Data→Data, behoudt alpha), off-main aanroepbaar. `EditorView.runBoostResolution`
  vertakt nu: `mode == .localOnly` → `runLocalBoost` (geen `allowCloudFeature`-gate, geen credit,
  undo'baar via `ImageEnhanceUndo`, off-main via `Task.detached`); anders het bestaande cloud-pad.
  Voorheen kreeg een localOnly-gebruiker de "enable online"-gate en kón niet boosten. `EditColorPanel`
  toont op "Boost" "Free" i.p.v. een credit-chip in localOnly. `LocalUpscaleTests` (2, groen): 2×
  maat + geldige PNG. DoD groen (build-v2.sh "alles groen"; 9/9 Avatar2-tests inc. shaders/render).

- `LocalUpscale` (Core Image): Lanczos 2× + unsharp-mask op de cutout-PNG (Data→Data, off-main).
  Geen model-download/app-bloat; eerlijk "scherper + groter" zonder AI-hallucinatie. Behoudt alpha.
- `EditorView.runBoostResolution`: bij `PrivacyPreferences2.shared.mode == .localOnly` → lokale
  route (geen `allowCloudFeature`-gate, geen credit, undo'baar); anders het bestaande cloud-pad.
- Credit-chip op "Boost" toont in localOnly "Free" i.p.v. een credit-kost.
- DoD: beide targets bouwen, een test die `LocalUpscale` een groter beeld oplevert, tests groen,
  Result-regel.
