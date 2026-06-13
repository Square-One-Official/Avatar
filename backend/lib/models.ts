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
 * unversioned slug 404s on `replicate.run` — BiRefNet, DeOldify) or an
 * unversioned official slug (flux-fill-pro). Upgrading a model = changing
 * one line here.
 *
 * NOTE for E09.1 (bakeoff) / E15.5 (dev model-picker): alternative models
 * register here as extra `models` entries. An alternative must accept the
 * same input payload as the feature's default — if it doesn't, give it an
 * adapter in lib/replicate.ts first and only then register it.
 */

export type CloudFeature = "cutout" | "colorize" | "fill_body" | "stylize";

export interface ModelEntry {
  /** Replicate ref: unversioned `owner/slug` or pinned `owner/slug:version`. */
  ref: string;
  /** Human-readable label for the dev model-picker (E15.5). */
  label: string;
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
    // Voorlopig; de bakeoff-uitkomst bepaalt het echte default (mag per
    // feature verschillen — stijl ≠ kleding ≠ haar, zie E09.1).
    defaultModel: "nano-banana",
    models: {
      "nano-banana": {
        ref: "google/nano-banana",
        label: "Nano Banana (Gemini 2.5 Flash Image)",
      },
      "flux-2-pro": {
        ref: "black-forest-labs/flux-2-pro",
        label: "FLUX.2 [pro]",
      },
      "gpt-image-1.5": {
        ref: "openai/gpt-image-1.5",
        label: "GPT Image 1.5",
      },
    },
    // E14.3: generatief standaardtarief (4); premium-features (7) krijgen
    // bij dat besluit hun eigen registratie.
    credits: 4,
    requiresCloud: true,
  },
};

/** Resolve a feature's default model ref. */
export function defaultModelRef(feature: CloudFeature): string {
  const reg = MODEL_REGISTRY[feature];
  return reg.models[reg.defaultModel].ref;
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
