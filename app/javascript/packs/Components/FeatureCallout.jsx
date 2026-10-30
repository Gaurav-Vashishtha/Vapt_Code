import React, { useState } from "react";
import {
  BlockStack,
  Button,
  Card,
  InlineStack,
  Modal,
  Text,
} from "@shopify/polaris";
import styled from "styled-components";
import I18n from "../i18n-lang";

const DOCS_URL = "https://codking.tech/documentation/";

/* Illustrations are drawn here rather than shipped as images: they inherit the
   admin's colours, stay sharp on every screen and add nothing to the bundle. */
/* Flush against the card edge, like the panel on Shopify's own callouts. */
const Art = styled.div`
  /* One panel size on every screen: 288x193, the 1370x920 ratio of the source
     photos. A drawn illustration sits in the same box as a photo, so the
     callout is the same height whichever a screen uses. */
  flex: 0 0 288px;
  aspect-ratio: 1370 / 920;
  align-self: flex-start;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: ${(props) => (props.$image ? "0" : "18px 26px")};
  overflow: hidden;
  background: linear-gradient(140deg, #eceefb 0%, #dfe3f6 100%);

  img {
    display: block;
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  svg {
    display: block;
    width: 100%;
    height: auto;
    max-height: 100%;
  }

  @media (max-width: 640px) {
    display: none;
  }
`;

const Row = styled.div`
  display: flex;
  align-items: stretch;
`;

const Main = styled.div`
  flex: 1;
  min-width: 0;
  padding: 20px 24px;
  align-self: flex-start;
`;

const VideoFrame = styled.div`
  position: relative;
  width: 100%;
  padding-top: 56.25%;
  overflow: hidden;
  border-radius: 8px;
  background: #000;

  iframe {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    border: 0;
  }
`;

const ART_BLOB = "#e5e3f7";
const ART_ACCENT = "#f5a623";
const ART_LINE = "#4a4a7c";

/** Phone with an OTP code — the checkout widget. */
const WidgetArt = () => (
  <svg
    viewBox="0 0 180 120"
    preserveAspectRatio="xMidYMid meet"
    role="presentation"
    focusable="false"
  >
    <ellipse cx="96" cy="60" rx="58" ry="52" fill={ART_BLOB} />
    <rect
      x="52"
      y="14"
      width="62"
      height="96"
      rx="10"
      fill="#fff"
      stroke={ART_LINE}
      strokeWidth="3"
    />
    <rect x="74" y="22" width="18" height="4" rx="2" fill={ART_LINE} />
    <rect x="62" y="38" width="42" height="5" rx="2.5" fill={ART_BLOB} />
    <rect x="62" y="49" width="28" height="5" rx="2.5" fill={ART_BLOB} />
    {[0, 1, 2, 3].map((i) => (
      <rect
        key={i}
        x={62 + i * 11}
        y="64"
        width="8"
        height="12"
        rx="2"
        fill="#fff"
        stroke={ART_LINE}
        strokeWidth="2"
      />
    ))}
    <rect x="62" y="86" width="42" height="12" rx="6" fill={ART_ACCENT} />
    <circle cx="128" cy="40" r="16" fill="#fff" stroke={ART_LINE} strokeWidth="3" />
    <path
      d="M121 40l5 5 9-10"
      fill="none"
      stroke={ART_LINE}
      strokeWidth="3"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  </svg>
);

/** Paint roller over a swatch — customization. */
const CustomizeArt = () => (
  <svg
    viewBox="0 0 180 120"
    preserveAspectRatio="xMidYMid meet"
    role="presentation"
    focusable="false"
  >
    <ellipse cx="90" cy="62" rx="56" ry="50" fill={ART_BLOB} />
    <path d="M96 18h34v14H96z" fill={ART_ACCENT} />
    <rect
      x="60"
      y="26"
      width="52"
      height="14"
      rx="4"
      fill="#fff"
      stroke={ART_LINE}
      strokeWidth="3"
    />
    <path
      d="M56 33h-8v22a6 6 0 006 6h6"
      fill="none"
      stroke={ART_LINE}
      strokeWidth="3"
      strokeLinecap="round"
    />
    <rect x="50" y="60" width="12" height="26" rx="4" fill="#fff" stroke={ART_LINE} strokeWidth="3" />
    <rect
      x="76"
      y="52"
      width="58"
      height="52"
      rx="4"
      fill="#fff"
      stroke={ART_LINE}
      strokeWidth="3"
    />
    <path d="M76 52h58l-10 16H86z" fill={ART_ACCENT} />
    <rect x="86" y="76" width="30" height="4" rx="2" fill={ART_BLOB} />
    <rect x="86" y="86" width="20" height="4" rx="2" fill={ART_BLOB} />
    <circle cx="124" cy="88" r="5" fill={ART_ACCENT} />
  </svg>
);

/** Open book — documentation. */
const DocsArt = () => (
  <svg
    viewBox="0 0 180 120"
    preserveAspectRatio="xMidYMid meet"
    role="presentation"
    focusable="false"
  >
    <ellipse cx="90" cy="62" rx="56" ry="48" fill={ART_BLOB} />
    <path
      d="M40 34c16-6 30-6 50 4v52c-20-10-34-10-50-4z"
      fill="#fff"
      stroke={ART_LINE}
      strokeWidth="3"
      strokeLinejoin="round"
    />
    <path
      d="M140 34c-16-6-30-6-50 4v52c20-10 34-10 50-4z"
      fill="#fff"
      stroke={ART_LINE}
      strokeWidth="3"
      strokeLinejoin="round"
    />
    <path d="M52 48h24M52 60h24M104 48h24M104 60h24" stroke={ART_BLOB} strokeWidth="4" strokeLinecap="round" />
    <circle cx="90" cy="26" r="9" fill={ART_ACCENT} />
  </svg>
);

/** Card with a part-paid coin — partial payments and discounts. */
const PaymentsArt = () => (
  <svg
    viewBox="0 0 180 120"
    preserveAspectRatio="xMidYMid meet"
    role="presentation"
    focusable="false"
  >
    <ellipse cx="90" cy="60" rx="58" ry="50" fill={ART_BLOB} />
    <rect
      x="38"
      y="34"
      width="86"
      height="56"
      rx="8"
      fill="#fff"
      stroke={ART_LINE}
      strokeWidth="3"
    />
    <path d="M38 48h86" stroke={ART_LINE} strokeWidth="3" />
    <rect x="48" y="62" width="26" height="5" rx="2.5" fill={ART_BLOB} />
    <rect x="48" y="74" width="16" height="5" rx="2.5" fill={ART_BLOB} />
    <circle cx="126" cy="76" r="20" fill="#fff" stroke={ART_LINE} strokeWidth="3" />
    <path
      d="M126 56a20 20 0 010 40z"
      fill={ART_ACCENT}
      stroke={ART_LINE}
      strokeWidth="3"
      strokeLinejoin="round"
    />
  </svg>
);

/** Price tag with a percent — discounts. */
const DiscountArt = () => (
  <svg
    viewBox="0 0 180 120"
    preserveAspectRatio="xMidYMid meet"
    role="presentation"
    focusable="false"
  >
    <ellipse cx="90" cy="60" rx="56" ry="50" fill={ART_BLOB} />
    <path
      d="M92 24H52a8 8 0 00-8 8v40a8 8 0 002.3 5.7l40 40a8 8 0 0011.4 0l40-40a8 8 0 000-11.4l-40-40A8 8 0 0092 24z"
      fill="#fff"
      stroke={ART_LINE}
      strokeWidth="3"
      strokeLinejoin="round"
    />
    <circle cx="66" cy="46" r="7" fill={ART_ACCENT} stroke={ART_LINE} strokeWidth="3" />
    <path d="M86 82l26-26" stroke={ART_LINE} strokeWidth="3" strokeLinecap="round" />
    <circle cx="86" cy="56" r="6" fill="none" stroke={ART_LINE} strokeWidth="3" />
    <circle cx="112" cy="82" r="6" fill="none" stroke={ART_LINE} strokeWidth="3" />
  </svg>
);

/** Card paid up front, with a percent badge — prepaid discount. */
const PrepaidArt = () => (
  <svg
    viewBox="0 0 180 120"
    preserveAspectRatio="xMidYMid meet"
    role="presentation"
    focusable="false"
  >
    <ellipse cx="88" cy="60" rx="56" ry="50" fill={ART_BLOB} />
    <rect
      x="34"
      y="32"
      width="94"
      height="58"
      rx="8"
      fill="#fff"
      stroke={ART_LINE}
      strokeWidth="3"
    />
    <path d="M34 48h94" stroke={ART_LINE} strokeWidth="3" />
    <rect x="46" y="62" width="30" height="6" rx="3" fill={ART_BLOB} />
    <rect x="46" y="74" width="18" height="6" rx="3" fill={ART_BLOB} />
    <circle cx="126" cy="80" r="20" fill={ART_ACCENT} stroke={ART_LINE} strokeWidth="3" />
    <path d="M119 87l14-14" stroke={ART_LINE} strokeWidth="3" strokeLinecap="round" />
    <circle cx="120" cy="74" r="3.5" fill={ART_LINE} />
    <circle cx="132" cy="86" r="3.5" fill={ART_LINE} />
  </svg>
);

/** Message bubbles leaving a phone — customer notifications. */
const NotifyArt = () => (
  <svg
    viewBox="0 0 180 120"
    preserveAspectRatio="xMidYMid meet"
    role="presentation"
    focusable="false"
  >
    <ellipse cx="88" cy="60" rx="58" ry="50" fill={ART_BLOB} />
    <rect
      x="30"
      y="16"
      width="58"
      height="90"
      rx="10"
      fill="#fff"
      stroke={ART_LINE}
      strokeWidth="3"
    />
    <rect x="50" y="24" width="18" height="4" rx="2" fill={ART_LINE} />
    <rect x="40" y="40" width="38" height="5" rx="2.5" fill={ART_BLOB} />
    <rect x="40" y="52" width="26" height="5" rx="2.5" fill={ART_BLOB} />
    <path
      d="M96 30h44a6 6 0 016 6v22a6 6 0 01-6 6h-26l-12 10V64h-6a6 6 0 01-6-6V36a6 6 0 016-6z"
      fill="#fff"
      stroke={ART_LINE}
      strokeWidth="3"
      strokeLinejoin="round"
    />
    <path d="M106 42h26M106 52h16" stroke={ART_BLOB} strokeWidth="4" strokeLinecap="round" />
    <circle cx="136" cy="84" r="14" fill={ART_ACCENT} stroke={ART_LINE} strokeWidth="3" />
    <path
      d="M130 84l4 4 8-8"
      fill="none"
      stroke={ART_LINE}
      strokeWidth="3"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  </svg>
);

/** A verified chat bubble on a handset — the store's own WhatsApp number. */
const WhatsappArt = () => (
  <svg
    viewBox="0 0 180 120"
    preserveAspectRatio="xMidYMid meet"
    role="presentation"
    focusable="false"
  >
    <ellipse cx="90" cy="60" rx="58" ry="50" fill={ART_BLOB} />
    <path
      d="M52 24h76a10 10 0 0110 10v40a10 10 0 01-10 10H82L60 100V84h-8a10 10 0 01-10-10V34a10 10 0 0110-10z"
      fill="#fff"
      stroke={ART_LINE}
      strokeWidth="3"
      strokeLinejoin="round"
    />
    <path
      d="M74 46c0 16 12 28 28 28l6-6-8-6-5 4a20 20 0 01-13-13l4-5-6-8-6 6z"
      fill={ART_ACCENT}
      stroke={ART_LINE}
      strokeWidth="3"
      strokeLinejoin="round"
    />
    <circle cx="134" cy="30" r="15" fill="#fff" stroke={ART_LINE} strokeWidth="3" />
    <path
      d="M127 30l5 5 9-10"
      fill="none"
      stroke={ART_LINE}
      strokeWidth="3"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  </svg>
);

/** YouTube play mark, so a video link reads as one at a glance. */
const YouTubeIcon = () => (
  <svg
    viewBox="0 0 24 17"
    width="18"
    height="13"
    aria-hidden="true"
    focusable="false"
    style={{ display: "block", flex: "0 0 auto" }}
  >
    <path
      fill="#FF0000"
      d="M23.5 2.6a3 3 0 0 0-2.1-2.1C19.5 0 12 0 12 0S4.5 0 2.6.5A3 3 0 0 0 .5 2.6C0 4.5 0 8.4 0 8.4s0 3.9.5 5.8a3 3 0 0 0 2.1 2.1c1.9.5 9.4.5 9.4.5s7.5 0 9.4-.5a3 3 0 0 0 2.1-2.1c.5-1.9.5-5.8.5-5.8s0-3.9-.5-5.8Z"
    />
    <path fill="#FFFFFF" d="M9.6 12 15.8 8.4 9.6 4.8V12Z" />
  </svg>
);

/** UI customization: the widget with its logo, colours and wording. Drawn at
 *  the panel's 1370x920 ratio so it fills the box like a photo. */
const UI_BRAND = "#5b4bdb";
const UI_INK = "#2e2a5c";
const UiCustomizeArt = () => (
  <svg
    viewBox="0 0 274 184"
    preserveAspectRatio="xMidYMid slice"
    role="presentation"
    focusable="false"
  >
    <defs>
      <linearGradient id="uica-bg" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stopColor="#efedfd" />
        <stop offset="1" stopColor="#dcd8f7" />
      </linearGradient>
      <filter id="uica-shadow" x="-50%" y="-50%" width="200%" height="200%">
        <feDropShadow dx="0" dy="3" stdDeviation="4" floodColor="#3b2f9e" floodOpacity="0.16" />
      </filter>
    </defs>

    <rect width="274" height="184" fill="url(#uica-bg)" />

    {/* The widget */}
    <g filter="url(#uica-shadow)">
      <rect x="93" y="22" width="88" height="140" rx="14" fill="#ffffff" />
    </g>
    <circle cx="108" cy="41" r="6" fill={UI_BRAND} />
    <rect x="119" y="38.5" width="36" height="5" rx="2.5" fill={UI_INK} />
    <rect x="93" y="54" width="88" height="10" fill={UI_BRAND} />
    <rect x="103" y="78" width="56" height="6" rx="3" fill={UI_INK} />
    <rect x="103" y="90" width="68" height="4" rx="2" fill="#cfcbee" />
    <rect x="103" y="99" width="46" height="4" rx="2" fill="#cfcbee" />
    <rect x="103" y="130" width="68" height="16" rx="5" fill={UI_BRAND} />
    <rect x="125" y="136.5" width="24" height="3.5" rx="1.75" fill="#ffffff" />

    {/* Colours */}
    {[UI_BRAND, "#10b981", "#f59e0b"].map((fill, i) => (
      <g key={fill} filter="url(#uica-shadow)">
        <circle cx="58" cy={70 + i * 22} r="8" fill={fill} stroke="#ffffff" strokeWidth="3" />
      </g>
    ))}

    {/* Wording */}
    <g filter="url(#uica-shadow)">
      <circle cx="216" cy="92" r="20" fill="#ffffff" />
    </g>
    <text x="216" y="98" textAnchor="middle" fontFamily="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" fontSize="16" fontWeight="700" fill={UI_BRAND}>
      Aa
    </text>
  </svg>
);

/** WhatsApp campaigns: one message going out to a group of customers. Same
 *  full-bleed format and theme background as UiCustomizeArt; green only marks
 *  the WhatsApp chat itself. */
const WA_GREEN = "#25a45a";
const CampaignsArt = () => (
  <svg
    viewBox="0 0 274 184"
    preserveAspectRatio="xMidYMid slice"
    role="presentation"
    focusable="false"
  >
    <defs>
      <linearGradient id="waca-bg" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stopColor="#efedfd" />
        <stop offset="1" stopColor="#dcd8f7" />
      </linearGradient>
      <filter id="waca-shadow" x="-50%" y="-50%" width="200%" height="200%">
        <feDropShadow dx="0" dy="3" stdDeviation="4" floodColor="#3b2f9e" floodOpacity="0.16" />
      </filter>
    </defs>

    <rect width="274" height="184" fill="url(#waca-bg)" />

    {/* The chat */}
    <g filter="url(#waca-shadow)">
      <rect x="93" y="22" width="88" height="140" rx="14" fill="#ffffff" />
    </g>
    <path d="M93 36a14 14 0 0 1 14-14h60a14 14 0 0 1 14 14v12H93z" fill={WA_GREEN} />
    <circle cx="107" cy="36" r="5" fill="#ffffff" opacity="0.9" />
    <rect x="116" y="33.5" width="32" height="5" rx="2.5" fill="#ffffff" opacity="0.9" />
    <rect x="101" y="60" width="62" height="42" rx="7" fill="#eef8f1" />
    <rect x="107" y="66" width="50" height="16" rx="4" fill="#bfe6cc" />
    <rect x="107" y="87" width="44" height="4" rx="2" fill="#2f4a3a" opacity="0.75" />
    <rect x="107" y="94" width="30" height="4" rx="2" fill="#2f4a3a" opacity="0.35" />
    <rect x="101" y="108" width="62" height="14" rx="5" fill="#ffffff" stroke="#cdebd7" strokeWidth="1.2" />
    <rect x="118" y="113" width="28" height="4" rx="2" fill={WA_GREEN} />
    <rect x="125" y="132" width="48" height="16" rx="6" fill="#d9fdd3" />
    <rect x="131" y="138" width="30" height="4" rx="2" fill="#2f4a3a" opacity="0.6" />

    {/* The audience */}
    {[UI_BRAND, "#f59e0b", "#10b981"].map((fill, i) => (
      <g key={fill} filter="url(#waca-shadow)">
        <circle cx="58" cy={70 + i * 22} r="9" fill={fill} stroke="#ffffff" strokeWidth="3" />
      </g>
    ))}

    {/* Send */}
    <g filter="url(#waca-shadow)">
      <circle cx="216" cy="92" r="20" fill={UI_BRAND} />
    </g>
    <path d="M207 92.5l18-8.5-6.5 18-3.2-6.3z" fill="#ffffff" />
  </svg>
);

const ART = {
  widget: WidgetArt,
  customize: CustomizeArt,
  uiCustomize: UiCustomizeArt,
  campaigns: CampaignsArt,
  docs: DocsArt,
  payments: PaymentsArt,
  discount: DiscountArt,
  prepaid: PrepaidArt,
  notify: NotifyArt,
  whatsapp: WhatsappArt,
};

// Scenes that fill the panel edge to edge, like a photo.
const FULL_BLEED_ART = new Set(["uiCustomize", "campaigns"]);

const toEmbedUrl = (url) => {
  if (!url) return "";
  if (url.includes("youtube.com/embed/")) return url;
  const match = url.match(
    /(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/|&v=)([^#&?/]+)/
  );
  return match ? `https://www.youtube.com/embed/${match[1]}` : url;
};

/**
 * The callout that opens a feature screen: what it does, its status, the
 * actions that turn it on, and the help that used to sit in a side rail —
 * Learn more opens the docs, Watch video plays inline.
 */
const FeatureCallout = ({
  title,
  description,
  badge,
  toggle,
  illustration = "widget",
  // A photo for this feature. Takes the panel at 290x210; without one the
  // line-art above is used instead.
  image,
  docsUrl = DOCS_URL,
  videoUrl,
  // [{ url, label }] when a feature has more than one walkthrough.
  videos,
  showChat = false,
  actions,
  children,
}) => {
  const [activeVideo, setActiveVideo] = useState(null);
  const Illustration = ART[illustration] || WidgetArt;

  const videoList =
    videos && videos.length
      ? videos
      : videoUrl
      ? [
          {
            url: videoUrl,
            label: I18n.t("documentation.watch_video", {
              defaultValue: "Watch video",
            }),
          },
        ]
      : [];

  return (
    <>
      <Card padding="0">
        <Row>
          <Art $image={!!image || FULL_BLEED_ART.has(illustration)}>
            {image ? <img src={image} alt="" loading="lazy" /> : <Illustration />}
          </Art>

          <Main>
            <BlockStack gap="200">
              <BlockStack gap="100">
                <InlineStack align="space-between" blockAlign="center" gap="400">
                  <InlineStack gap="200" blockAlign="center">
                    <Text variant="headingMd" as="h2">
                      {title}
                    </Text>
                    {badge}
                  </InlineStack>
                  {toggle}
                </InlineStack>
                {description && (
                  <Text variant="bodyMd" tone="subdued" as="p">
                    {description}
                  </Text>
                )}
              </BlockStack>

              {children}

              <InlineStack gap="300" blockAlign="center">
                {actions}
                {docsUrl && (
                  <Button variant="plain" onClick={() => window.open(docsUrl, "_blank")}>
                    {I18n.t("documentation.learn_more", {
                      defaultValue: "Learn more",
                    })}
                  </Button>
                )}
                {videoList.map((video) => (
                  <Button
                    key={video.url}
                    variant="plain"
                    onClick={() => setActiveVideo(video)}
                  >
                    <InlineStack gap="150" blockAlign="center" wrap={false}>
                      <YouTubeIcon />
                      <span>{video.label}</span>
                    </InlineStack>
                  </Button>
                ))}
                {showChat && (
                  <Button
                    variant="plain"
                    onClick={() => window.$crisp?.push(["do", "chat:open"])}
                  >
                    {I18n.t("admin.chat_with_us", {
                      defaultValue: "Chat with us",
                    })}
                  </Button>
                )}
              </InlineStack>
            </BlockStack>
          </Main>
        </Row>
      </Card>

      <Modal
        open={!!activeVideo}
        onClose={() => setActiveVideo(null)}
        title={activeVideo ? activeVideo.label : title}
        size="large"
      >
        <Modal.Section>
          <VideoFrame>
            {activeVideo && (
              <iframe
                src={`${toEmbedUrl(activeVideo.url)}?autoplay=1&rel=0`}
                title={activeVideo.label}
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                allowFullScreen
              />
            )}
          </VideoFrame>
        </Modal.Section>
      </Modal>
    </>
  );
};

export default FeatureCallout;
