/**
 * MODEL_REGISTRY — single source of truth for every cloud model the backend
 * can run (E01.10). Per feature this holds:
 *
 *   - the whitelist of runnable models (override key → Replicate ref), so
 *     the dev-only `model_override` request parameter can never reach an
 *     unregistered slug;
 *   - the credit price per call (the E14.3 tariff lives here, nowhere else);
 *   - `requiresCloud`, which /v1/account-adjacent surfaces and the client's
 *     CreditMeter expose per action (E03.7 cloud-glyph).
 *
 * Refs are either a pinned `slug:versionhash` (community models whose
 * unversioned slug 404s on `replicate.run` — BiRefNet, DeOldify,
 * Real-ESRGAN, Crystal Upscaler) or an unversioned official slug
 * (flux-fill-pro). Upgrading a model = changing one line here.
 *
 * NOTE for E09.1 (bakeoff) / E15.5 (dev model-picker): alternative models
 * register here as extra `models` entries. An alternative must accept the
 * same input payload as the feature's default — if it doesn't, give it an
 * adapter in lib/replicate.ts first and only then register it.
 */

import { GPT_IMAGE_ASPECTS, GPT_IMAGE_2_ASPECTS, type FixedAspect } from "./aspects.js";

export type CloudFeature = "cutout" | "colorize" | "fill_body" | "stylize" | "upscale" | "generate_background";

export interface ModelEntry {
  /** Replicate ref: unversioned `owner/slug` or pinned `owner/slug:version`. */
  ref: string;
  /** Human-readable label for the dev model-picker (E15.5). */
  label: string;
  /**
   * E55.1: gezet wanneer het model de input-ratio NIET kan aanhouden (vaste
   * ratio-set i.p.v. `match_input_image`) — /v1/stylize pakt dan het
   * pad→generate→crop-contract (lib/image.ts) met déze set als paddoelen,
   * zodat de response-ratio altijd de request-ratio is. Afwezig = het model
   * volgt de input zelf.
   */
  fixedAspects?: FixedAspect[];
}

export interface FeatureRegistration {
  /** Key into `models` used when no (honoured) override is supplied. */
  defaultModel: string;
  /** Override-whitelist: alleen deze keys zijn aanroepbaar via model_override. */
  models: Record<string, ModelEntry>;
  /**
   * Credits charged per call. Mirrors today's live deduction (1 everywhere);
   * the E14.3 tarieventabel (cutout/colorize 1, fill_body 2, generatief 4–5)
   * lands by changing these numbers when CreditMeter ships — endpoints
   * already read the price from here.
   */
  credits: number;
  /** True when the action cannot run on-device (E03.7 cloud-glyph). */
  requiresCloud: boolean;
}

export const MODEL_REGISTRY: Record<CloudFeature, FeatureRegistration> = {
  cutout: {
    defaultModel: "birefnet",
    models: {
      // BiRefNet — academic gold standard for portrait matting; fine alpha
      // at hair boundaries. Pinned: unversioned slug 404s for this
      // community model. New hash: https://replicate.com/men1scus/birefnet/versions
      birefnet: {
        ref: "men1scus/birefnet:f74986db0355b58403ed20963af156525e2891ea3c2d499bfbfb2a28cd87c5d7",
        label: "BiRefNet",
      },
    },
    credits: 1,
    requiresCloud: true,
  },
  colorize: {
    defaultModel: "deoldify",
    models: {
      // DeOldify — long-running standard for B&W colorization. Pinned for
      // the same 404 reason as BiRefNet. New hash:
      // https://replicate.com/arielreplicate/deoldify_image/versions
      deoldify: {
        ref: "arielreplicate/deoldify_image:0da600fab0c45a66211339f1c16b71345d22f26ef5fea3dca1bb90bb5711e950",
        label: "DeOldify",
      },
    },
    credits: 1,
    requiresCloud: true,
  },
  fill_body: {
    defaultModel: "flux-fill-pro",
    models: {
      // Official BFL model: unversioned slug works on replicate.run. Pin a
      // hash from https://replicate.com/black-forest-labs/flux-fill-pro/versions
      // if a 404 appears.
      "flux-fill-pro": {
        ref: "black-forest-labs/flux-fill-pro",
        label: "FLUX.1 Fill [pro]",
      },
    },
    // E14.3: 1 → 2 (FLUX Fill ~$0,05/call, kosten-proportioneel tarief;
    // spiegelt CreditMeter.fillBody). Landt op productie bij de volgende
    // E13.0-port, niet nu.
    credits: 2,
    requiresCloud: true,
  },
  // Instruction-edit (stijlen + retouch). De drie entries zijn de E09.1
  // bakeoff-armen; /v1/stylize is dev-only tot de bakeoff een definitief
  // default per feature heeft aangewezen (E09.2 haalt de gate weg). Alle
  // drie zijn officiële, unversioned slugs — geen pinning nodig. De
  // payload-verschillen per arm leven in stylizeInputFor (lib/replicate.ts).
  stylize: {
    // E55.2 + gpt-image-2-swap (besluiten Thierry 2026-08-02): het OpenAI-
    // model is de default — beste stijlmatch, zeker met stijlreferenties;
    // het E09.1-bezwaar (herkaderen) is opgelost door het E55.1-aspect-
    // contract, en 2.0's ruimere ratio-set (incl. 3:4/9:16) maakt het pad
    // dun tot nul. Nieuwe clients sturen `generation_model` alleen bij een
    // expliciete keuze, dus deze default regeert de vloot; env-override
    // hieronder (STYLIZE_DEFAULT_MODEL) is de rollback-hendel zonder
    // app-update. 1.5 blijft registry-only (bakeoff-arm + env-fallback):
    // 2.0 dropte de `input_fidelity`-parameter, dus identiteitsbehoud is
    // het punt dat de 55.7-bakeoff moet bewijzen.
    defaultModel: "gpt-image-2",
    models: {
      "nano-banana": {
        ref: "google/nano-banana",
        label: "Nano Banana (Gemini 2.5 Flash Image)",
      },
      "flux-2-pro": {
        ref: "black-forest-labs/flux-2-pro",
        label: "FLUX.2 [pro]",
      },
      "gpt-image-2": {
        ref: "openai/gpt-image-2",
        label: "GPT Image 2",
        fixedAspects: GPT_IMAGE_2_ASPECTS,
      },
      // Registry-only (niet user-selectable): 1.5 heeft nog wél de expliciete
      // input_fidelity-hendel — de identity-vergelijkingsarm in 55.7 en de
      // nood-fallback via STYLIZE_DEFAULT_MODEL als 2.0 daar doorheen zakt.
      "gpt-image-1.5": {
        ref: "openai/gpt-image-1.5",
        label: "GPT Image 1.5",
        fixedAspects: GPT_IMAGE_ASPECTS,
      },
      // E32.1 face-bakeoff-arm (dev-only). ByteDance Seedream 4 — unified
      // generate/edit, accepteert reference-images voor instruction-edit.
      // Adapter in stylizeInputFor (lib/replicate.ts). Unversioned officiële
      // slug; pin een hash bij een 404 via replicate.com/bytedance/seedream-4.
      seedream: {
        ref: "bytedance/seedream-4",
        label: "Seedream 4",
      },
    },
    // E14.3: generatief standaardtarief (4); premium-features (7) krijgen
    // bij dat besluit hun eigen registratie.
    credits: 4,
    requiresCloud: true,
  },
  // E10.3 + E41.1 + E41.4: Boost resolution. Default = topaz (Gigapixel High
  // Fidelity V2): won de E41.4-bakeoff (2026-07-03, 4 armen × 5 E09-
  // portretten, live Replicate-runs door de echte pipeline) op detailbehoud
  // + natuurlijke huidtextuur zonder identiteitsdrift; 8–15s per run.
  // real-esrgan bleef ook zonder face_enhance de "plastic" verliezer.
  // Crystal-422-naschrift (2026-07-03): de in E41.3 gepinde hash wás de
  // huidige latest (zonder login verifieerbaar — `latest_version` staat in
  // de HTML van de modelpagina). 422 "Invalid version or not permitted"
  // betekent dat dit model geen versioned runs toestaat → unversioned ref,
  // met een expliciete uitzondering op de pin-guard in models-smoke.ts;
  // unversioned live bevestigd in de bakeoff.
  // NB: upscaleInputFor (lib/replicate.ts) matcht op het slug-prefix.
  upscale: {
    defaultModel: "topaz",
    models: {
      topaz: {
        ref: "topazlabs/image-upscale",
        label: "Topaz Gigapixel (High Fidelity V2)",
      },
      "google-upscaler": {
        ref: "google/upscaler",
        label: "Google Upscaler (Imagen)",
      },
      "crystal-upscaler": {
        ref: "philz1337x/crystal-upscaler",
        label: "Crystal Upscaler (portrait)",
      },
      "real-esrgan": {
        ref: "nightmareai/real-esrgan:f121d640bd286e1fdc67f9799164c1d5be36ff74576ee11c803ae5b665dd46aa",
        label: "Real-ESRGAN",
      },
    },
    // E41.5: upscale rekent per tier af — zie UPSCALE_TIERS in api/v1/upscale.ts
    // (regular=1, high=3). Dit veld is voor upscale alleen nog de registry-vorm.
    credits: 1,
    requiresCloud: true,
  },
  generate_background: {
    defaultModel: "nano-banana",
    models: {
      "nano-banana": {
        ref: "google/nano-banana",
        label: "Nano Banana (Gemini 2.5 Flash Image)",
      },
      "gpt-image-2": {
        ref: "openai/gpt-image-2",
        label: "GPT Image 2",
        fixedAspects: GPT_IMAGE_2_ASPECTS,
      },
      // Registry-only — zelfde reden als bij stylize.
      "gpt-image-1.5": {
        ref: "openai/gpt-image-1.5",
        label: "GPT Image 1.5",
        fixedAspects: GPT_IMAGE_ASPECTS,
      },
    },
    credits: 2,
    requiresCloud: true,
  },
};

/**
 * E55.2: de stylize-default is env-stuurbaar. Alleen keys uit de
 * stylize-whitelist tellen; al het andere valt luid terug op de gegeven
 * code-default. Pure functie zodat models-smoke alle takken kan bewijzen
 * zonder env-gymnastiek.
 */
export function resolveStylizeDefaultModel(
  raw: string | undefined,
  models: Record<string, ModelEntry>,
  fallback: string,
): string {
  if (!raw) return fallback;
  if (models[raw]) return raw;
  console.warn(
    `[models] STYLIZE_DEFAULT_MODEL "${raw}" niet in de stylize-whitelist — default blijft ${fallback}`,
  );
  return fallback;
}

// Vloot-rollback-hendel (E55.8): `STYLIZE_DEFAULT_MODEL=nano-banana` (of
// `gpt-image-1.5` — registry-only maar whitelist-geldig) + redeploy zet
// niet-kiezers om zonder app-update. Ongezet = code-default hierboven.
MODEL_REGISTRY.stylize.defaultModel = resolveStylizeDefaultModel(
  process.env.STYLIZE_DEFAULT_MODEL,
  MODEL_REGISTRY.stylize.models,
  MODEL_REGISTRY.stylize.defaultModel,
);

/** Resolve a feature's default model ref. */
export function defaultModelRef(feature: CloudFeature): string {
  const reg = MODEL_REGISTRY[feature];
  return reg.models[reg.defaultModel].ref;
}

/**
 * E55.1: de vaste ratio-set van het model met deze ref, of null wanneer het
 * de input-ratio zelf aanhoudt. Lookup over de hele registry op slug (pinned
 * versies tellen als hetzelfde model); onbekende refs gelden als
 * input-volgend — het contract is een gpt-image-eigenschap, geen default.
 */
export function modelFixedAspects(ref: string): FixedAspect[] | null {
  const slug = ref.split(":")[0];
  for (const feature of Object.values(MODEL_REGISTRY)) {
    for (const entry of Object.values(feature.models)) {
      if (entry.ref.split(":")[0] === slug) {
        return entry.fixedAspects ?? null;
      }
    }
  }
  return null;
}

/** Houdt het model met deze ref de input-ratio aan? (afgeleide van hierboven) */
export function modelMatchesInputAspect(ref: string): boolean {
  return modelFixedAspects(ref) === null;
}

/**
 * Door gebruikers kiesbare generatie-modellen per feature (E15.6). I.t.t.
 * `model_override` (dev-only, hele whitelist) is dit een kleine, openbare
 * keuze: de Settings-rij "Generation model" laat de gebruiker schakelen
 * tussen het OpenAI-model (stylize-default sinds E55.2) en nano-banana.
 * Alleen deze keys mogen van een gewone gebruiker komen.
 */
export const USER_SELECTABLE_MODELS: Partial<Record<CloudFeature, string[]>> = {
  stylize: ["nano-banana", "gpt-image-2"],
  generate_background: ["nano-banana", "gpt-image-2"],
};

/**
 * Resolve de optionele, gebruikersgerichte `generation_model`-parameter naar
 * een Replicate-ref.
 *
 *   - geen/lege waarde → null (caller gebruikt de feature-default);
 *   - waarde gelijk aan de feature-default → null (zelfde gedrag, geen ruis);
 *   - waarde in de user-selectable whitelist → die ref;
 *   - onbekende/niet-toegestane waarde → null, stil genegeerd (geen oracle;
 *     valt terug op de default i.p.v. een 400 zoals de dev-override, want
 *     een verouderde client-voorkeur mag de feature niet breken).
 */
export function resolveGenerationModel(
  feature: CloudFeature,
  rawKey: unknown,
): string | null {
  if (typeof rawKey !== "string" || rawKey === "") return null;
  const reg = MODEL_REGISTRY[feature];
  if (rawKey === reg.defaultModel) return null;
  const allowed = USER_SELECTABLE_MODELS[feature] ?? [];
  if (!allowed.includes(rawKey)) {
    console.warn(`[models] generation_model not user-selectable feature=${feature} key=${rawKey}`);
    return null;
  }
  const entry = reg.models[rawKey];
  return entry ? entry.ref : null;
}

export class UnknownModelOverrideError extends Error {
  constructor(
    public readonly feature: CloudFeature,
    public readonly key: string,
  ) {
    super(`unknown model override "${key}" for feature "${feature}"`);
    this.name = "UnknownModelOverrideError";
  }
}

/**
 * Resolve the optional `model_override` request parameter to a Replicate ref.
 *
 *   - no/empty override → null (caller uses the feature default);
 *   - caller is not dev-allowlisted → null, override silently ignored — the
 *     parameter is a dev-tool, not API surface, so non-dev requests behave
 *     exactly as if it were absent (no oracle on the allowlist);
 *   - dev + key in the feature's whitelist → that model's ref;
 *   - dev + unknown key → UnknownModelOverrideError (endpoint maps to 400),
 *     because silently falling back would invalidate a bakeoff run.
 */
export function resolveModelOverride(
  feature: CloudFeature,
  rawKey: unknown,
  isDevUser: boolean,
): string | null {
  if (typeof rawKey !== "string" || rawKey === "") return null;
  if (!isDevUser) {
    console.warn(`[models] non-dev model_override ignored feature=${feature}`);
    return null;
  }
  const entry = MODEL_REGISTRY[feature].models[rawKey];
  if (!entry) throw new UnknownModelOverrideError(feature, rawKey);
  return entry.ref;
}
