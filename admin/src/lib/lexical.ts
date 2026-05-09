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
    case "link":     return `<a href="${escapeAttr(node.url ?? "")}" style="color: #9AB6F2;">${inner}</a>`;
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

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function escapeAttr(s: string): string {
  return escapeHtml(s).replace(/"/g, "&quot;");
}
