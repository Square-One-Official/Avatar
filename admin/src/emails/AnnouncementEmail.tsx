import * as React from "react";
import {
  Body,
  Container,
  Head,
  Heading,
  Hr,
  Html,
  Img,
  Link,
  Preview,
  Section,
  Text,
} from "@react-email/components";

type Props = {
  title: string;
  bodyHtml: string;
  imageUrl?: string | null;
  cta?: { label: string; url: string } | null;
  unsubscribeUrl?: string;
};

/**
 * React Email template for announcement newsletters. Renders a hero
 * image (when present), title, HTML body, optional CTA, and a footer
 * with the legally-required unsubscribe link.
 *
 * Width is locked at 560px — the sweet spot for Gmail's preview pane
 * without being squeezed on mobile clients.
 */
export default function AnnouncementEmail({
  title,
  bodyHtml,
  imageUrl,
  cta,
  unsubscribeUrl,
}: Props) {
  return (
    <Html>
      <Head />
      <Preview>{title}</Preview>
      <Body style={bodyStyle}>
        <Container style={containerStyle}>
          {imageUrl ? (
            <Img
              src={imageUrl}
              alt={title}
              width="560"
              height="315"
              style={heroStyle}
            />
          ) : null}

          <Section style={contentStyle}>
            <Heading style={headingStyle}>{title}</Heading>
            <Text
              style={paragraphStyle}
              dangerouslySetInnerHTML={{ __html: bodyHtml }}
            />

            {cta ? (
              <Section style={ctaWrapperStyle}>
                <Link href={cta.url} style={ctaButtonStyle}>
                  {cta.label}
                </Link>
              </Section>
            ) : null}
          </Section>

          <Hr style={hrStyle} />

          <Section style={footerStyle}>
            <Text style={footerTextStyle}>
              You're receiving this because you have an Aaavatar account.
              {unsubscribeUrl ? (
                <>
                  {" "}
                  <Link href={unsubscribeUrl} style={footerLinkStyle}>
                    Unsubscribe
                  </Link>
                  .
                </>
              ) : null}
            </Text>
          </Section>
        </Container>
      </Body>
    </Html>
  );
}

const bodyStyle: React.CSSProperties = {
  backgroundColor: "#0B0B0D",
  fontFamily:
    "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif",
  color: "#E6EAF1",
  margin: 0,
  padding: "32px 0",
};

const containerStyle: React.CSSProperties = {
  width: "560px",
  maxWidth: "100%",
  margin: "0 auto",
  backgroundColor: "#16161A",
  borderRadius: 12,
  overflow: "hidden",
};

const heroStyle: React.CSSProperties = {
  display: "block",
  width: "100%",
  height: "auto",
  objectFit: "cover",
};

const contentStyle: React.CSSProperties = {
  padding: "28px 28px 8px",
};

const headingStyle: React.CSSProperties = {
  fontSize: 24,
  fontWeight: 600,
  margin: "0 0 12px",
  color: "#FFFFFF",
};

const paragraphStyle: React.CSSProperties = {
  fontSize: 15,
  lineHeight: 1.55,
  color: "#C2C7D0",
  margin: 0,
};

const ctaWrapperStyle: React.CSSProperties = {
  marginTop: 24,
};

const ctaButtonStyle: React.CSSProperties = {
  display: "inline-block",
  backgroundColor: "#5E99FF",
  color: "#0B0B0D",
  padding: "11px 18px",
  borderRadius: 8,
  fontWeight: 600,
  fontSize: 14,
  textDecoration: "none",
};

const hrStyle: React.CSSProperties = {
  borderColor: "#2A2A2F",
  margin: "28px 0 0",
};

const footerStyle: React.CSSProperties = {
  padding: "16px 28px 24px",
};

const footerTextStyle: React.CSSProperties = {
  fontSize: 12,
  lineHeight: 1.5,
  color: "#7C8390",
  margin: 0,
};

const footerLinkStyle: React.CSSProperties = {
  color: "#9AB6F2",
  textDecoration: "underline",
};
