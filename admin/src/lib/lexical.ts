/**
 * Minimal Lexical → HTML renderer for newsletter bodies. Mirrors the
 * Markdown-emitter on the backend (`backend/lib/payload.ts`) but emits
 * HTML so React Email can drop it into a <Text dangerouslySetInnerHTML>
 * without a heavyweight Lexical-on-the-server dependency.
 *
 * Covers the node types the announcement body realistically uses:
 * paragraph, heading, list, list-item, link, bold/italic/strike/code.
 */
type LexicalNode = {
  type?: string;
  tag?: string;
  text?: string;
  format?: number;
  url?: string;
  listType?: string;
  children?: LexicalNode[];
};

type LexicalRoot = { root?: { children?: LexicalNode[] } };

export function lexicalToHtml(raw: unknown): string {
  if (typeof raw === "string") return escapeHtml(raw).replace(/\n/g, "<br/>");
  if (typeof raw !== "object" || raw === null) return "";
  const root = (raw as LexicalRoot).root;
  const children = Array.isArray(root?.children) ? root!.children! : [];
  return children.map(renderNode).join("");
}

function renderNode(node: LexicalNode): string {
  if (node.type === "text" && typeof node.text === "string") {
    let t = escapeHtml(node.text);
    const fmt = typeof node.format === "number" ? node.format : 0;
    if (fmt & 1) t = `<strong>${t}</strong>`;
    if (fmt & 2) t = `<em>${t}</em>`;
    if (fmt & 4) t = `<s>${t}</s>`;
    if (fmt & 16) t = `<code>${t}</code>`;
    return t;
  }
  const inner = (node.children ?? []).map(renderNode).join("");
  switch (node.type) {
    case "paragraph": return `<p style="margin: 0 0 12px;">${inner}</p>`;
    case "heading": {
      const level = headingLevel(node.tag);
      return `<h${level} style="margin: 18px 0 10px; color: #FFFFFF;">${inner}</h${level}>`;
    }
    case "link":     return `<a href="${escapeAttr(safeUrl(node.url))}" style="color: #9AB6F2;">${inner}</a>`;
    case "list":     return node.listType === "number" ? `<ol>${inner}</ol>` : `<ul>${inner}</ul>`;
    case "listitem": return `<li>${inner}</li>`;
    case "linebreak":return "<br/>";
    default:         return inner;
  }
}

function headingLevel(tag: string | undefined): number {
  if (!tag) return 2;
  const m = tag.match(/^h([1-6])$/);
  return m ? Number(m[1]) : 2;
}

// Schemes a newsletter link may legitimately use: web links, mail links, and
// the app's own `aaavatar://` deep link. Everything else (javascript:, data:,
// vbscript:, file:, …) is collapsed to a harmless anchor.
const ALLOWED_URL_SCHEMES = new Set(["http:", "https:", "mailto:", "aaavatar:"]);

/**
 * Collapse any non-navigational URL scheme to a harmless anchor before it
 * lands in an `href`. Admin authors are trusted, and the only render sink
 * today is email HTML (clients strip active content) — but a `javascript:`
 * or `data:` href in an author-supplied link would become stored XSS the
 * moment this HTML is ever shown in a browser/webview.
 *
 * Resolved with the WHATWG `URL` parser (against a dummy base) so we read the
 * exact scheme a browser would — this also neutralises the classic
 * control-character smuggling (`java&#9;script:`), since the parser strips
 * tab/newline before determining the scheme. Relative/scheme-less URLs resolve
 * to the dummy base's `https:` and are allowed; the original (escaped) string
 * is what we emit so legitimate relative links render unchanged.
 */
export function safeUrl(url: string | null | undefined): string {
  if (typeof url !== "string") return "#";
  const trimmed = url.trim();
  if (!trimmed) return "#";
  let scheme: string;
  try {
    scheme = new URL(trimmed, "https://aaavatar.invalid/").protocol;
  } catch {
    return "#";
  }
  return ALLOWED_URL_SCHEMES.has(scheme) ? trimmed : "#";
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function escapeAttr(s: string): string {
  return escapeHtml(s).replace(/"/g, "&quot;");
}
