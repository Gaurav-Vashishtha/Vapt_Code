import React from "react";
// import useViewport from "./utilities/useViewport";
import MobileLayout from "./MobileLayout/MobileLayout";
import DesktopLayout from "./DesktopLayout/DesktopLayout";
import useViewport from "../../utilities/useViewport";
import useOtpStore from "../../stores/otpStore";

function ModalLayout({ onClose }) {
  const { width } = useViewport();
  const { settings } = useOtpStore();
  const { preV2Theme } = settings;

  const themes = {
    theme1: {
      primary: "#c20000",
      primaryDark: "#b91c1c",
      secondary: "#ffffff",
      background: "#ffffff",
      cardBg: "#fff1f2",
      text: "#333333",
      border: "#e5e7eb",
    }, // Red Theme
    theme2: {
      primary: "#2563eb",
      primaryDark: "#1d4ed8",
      secondary: "#ffffff",
      background: "#f1f5f9",
      cardBg: "#e0f2fe",
      text: "#1f2937",
      border: "#cbd5e1",
    }, // Blue Theme
    theme3: {
      primary: "#10b981",
      primaryDark: "#047857",
      secondary: "#ffffff",
      background: "#f9fafb",
      cardBg: "#d1fae5",
      text: "#374151",
      border: "#d1d5db",
    }, // Green Theme
    theme4: {
      primary: "#f59e0b",
      primaryDark: "#d97706",
      secondary: "#ffffff",
      background: "#ffffff",
      cardBg: "#ffedd5",
      text: "#4b5563",
      border: "#e2e8f0",
    }, // Yellow Theme
    theme5: {
      primary: "#123646",
      primaryDark: "#000713",
      secondary: "#FFFFFF",
      background: "#F6F8FA",
      cardBg: "#E9EEF2",
      text: "#1E1E1E",
      border: "#D9DEE3",
    }, // Purple Theme
    theme6: {
      primary: "#f87171",
      primaryDark: "#ef4444",
      secondary: "#FFFFFF",
      background: "#ffffff",
      cardBg: "#fee2e2",
      text: "#374151",
      border: "#e5e7eb",
    }, // Coral Theme
    freshGreenTheme: {
      primary: "-webkit-linear-gradient(to right, #3c1053, #ad5389);",
      primaryDark: "#1e7b1e",
      secondary: "#ffffff",
      background: "#f5fff5",
      cardBg: "#e6f7e6",
      text: "#1e3a24",
      border: "#d1e7d1",
    }, // Fresh Green Theme

    crimsonTheme: {
      primary: "rgb(145, 14, 64)",
      primaryDark: "rgb(115, 11, 50)",
      secondary: "#ffffff",
      background: "rgb(255, 249, 252)",
      cardBg: "rgb(255, 235, 238)",
      text: "rgb(28, 27, 31)",
      border: "rgb(220, 38, 126)",
    }, // Crimson Theme
    // minimalWhiteTheme: {
    //   primary: "#123646", // "#000000", // Pure Black (button backgrounds, main highlights)
    //   primaryDark: "#000713", //"#1a1a1a", // Darker Black for contrast
    //   secondary: "#ffffff", // Pure White (secondary accents, background highlights)
    //   background: "#ffffff", // White background for general areas
    //   cardBg: "#f0f0f0", // Light Gray for cards to create slight distinction
    //   text: "#000000", // Black text for readability
    //   border: "#d1d1d1", // Light Gray for borders
    // }, // Minimal White Theme
    minimalWhiteTheme: {
      primary: "#123646",
      primaryDark: "#000713",
      secondary: "#FFFFFF",
      background: "#F6F8FA",
      cardBg: "#E9EEF2",
      text: "#1E1E1E",
      border: "#D9DEE3",
    },
    luxeGoldTheme: {
      primary: "#d4af37",
      primaryDark: "#b2942d",
      secondary: "#ffffff",
      background: "#ffffff",
      cardBg: "#fafafa",
      text: "#333333",
      border: "#d4af37",
    }, // Luxe Gold Theme
    freshGreenTheme: {
      primary: "#228b22",
      primaryDark: "#1e7b1e",
      secondary: "#ffffff",
      background: "#f5fff5",
      cardBg: "#e6f7e6",
      text: "#1e3a24",
      border: "#d1e7d1",
    }, // Fresh Green Theme
    theme7: {
      primary: "#ad5389", // Vibrant magenta
      primaryDark: "#3c1053", // Deep purple
      secondary: "#f5f5f5", // Light gray for better contrast
      background: "#fafafa", // Soft off-white for a premium feel
      cardBg: "#ffffff", // Clean white for a modern look
      text: "#333333", // Dark gray for better readability
      border: "#b38cb4", // Soft purple border to complement primary colors
    },
    theme8: {
      primary: "#3d0c02", // Deep reddish-brown
      primaryDark: "#b92e34", // Rich crimson
      secondary: "#f2dfd5", // Warm muted beige for a softer contrast
      background: "#fffaf5", // Soft off-white for a premium feel
      cardBg: "#fdf1eb", // Light pastel peach for subtle elegance
      text: "#2e1c15", // Deep espresso brown for high readability
      border: "#9c4f38", // Muted terracotta brown for a refined look
    },
    theme9: {
      primary: "#9a4622",
      primaryDark: "#bf5e35",
      secondary: "#ffffff",
      background: "#ffffff", // White background for general areas
      cardBg: "#f0f0f0",
      text: "#000000",
      border: "#d1d1d1", // Light Gray for borders
    },
    theme10: {
      primary: "#EF3D75",
      primaryDark: "#24010c",
      secondary: "#ffffff",
      background: "#ffffff",
      cardBg: "#f0f0f0",
      text: "#000000",
      border: "#d1d1d1",
    },
    theme11: {
      primary: "#4B2C5E", // Midnight Purple - buttons and highlights
      primaryDark: "#3A234B", // Darker tone of purple for hover/depth
      secondary: "#e3cbf4", // Moon Yellow - accent or top of gradient
      background: "#F6F8FA", // Keep existing off-white for main background
      cardBg: "#ffffff", // Cloud Lavender - soft contrast for card backgrounds
      text: "#1E1E1E", // Keep for readability
      border: "#D9DEE3", // Keep neutral light gray for structure
    },
    theme12: {
      primary: "#ffd247", //yellow theme
      primaryDark: "#b58906",
      secondary: "#fffcf4",
      background: "#ffffff",
      cardBg: "#f0f0f0",
      text: "#000000",
      border: "#d1d1d1",
    },
    theme13: {
      primary: "rgb(218 118 141)", //peach theme
      primaryDark: "rgb(191 96 121)",
      secondary: "#FFFFFF",
      background: "#F6F8FA",
      cardBg: "#E9EEF2",
      text: "#1E1E1E",
      border: "#D9DEE3",
    },
    themeBlackWhite: {
      primary: "#000000", // Pure black
      primaryDark: "#0a0a0a", // Slightly softer black for hover/active
      secondary: "#FFFFFF", // Pure white
      background: "#FFFFFF", // Page background
      cardBg: "#F9F9F9", // Very light gray for card background
      text: "#000000", // Black text
      border: "#E0E0E0", // Light gray border
    },
    deepForestTheme: {
      primary: "#1b3022", // Deep Forest Green
      primaryDark: "#132319", // Darker shade for hover
      secondary: "#ffffff", // Text on buttons
      background: "#f4f7f5", // Pale Mist background for the right side
      cardBg: "#ffffff", // Order summary card background
      text: "#1b3022", // Main titles and labels
      border: "#d1dcd4", // Input borders
      whatsappGreen: "#25D366", // Keep standard or use a themed forest green
    },
    modernBotanicalTheme: {
      primary: "#0a3d34", // Midnight Emerald
      primaryDark: "#052923", // Near-black Green
      secondary: "#ffffff",
      background: "#fafaf9", // Bone White (Very clean)
      cardBg: "#f1f3f1", // Light Sage wash for cards
      text: "#121a11", // Charcoal Green
      border: "#e2e8e2", // Thin silver-green border
    },
  };
  const resolvedTheme =
    typeof preV2Theme === "string" && themes[preV2Theme]
      ? themes[preV2Theme]
      : preV2Theme;

  // Decide which layout to render based on viewport width
  return width <= 768 ? (
    <MobileLayout theme={resolvedTheme} onClose={onClose} />
  ) : (
    <DesktopLayout theme={resolvedTheme} onClose={onClose} />
  );
}

export default ModalLayout;
