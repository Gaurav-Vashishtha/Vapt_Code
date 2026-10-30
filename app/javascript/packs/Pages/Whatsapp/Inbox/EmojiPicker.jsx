import React, { useState } from "react";
import { Box, Button, Popover } from "@shopify/polaris";
import { SmileyHappyMajor } from "@shopify/polaris-icons";
import { t } from "./format";

const EMOJI = [
  "😀", "😃", "😄", "😁", "😊", "🙂", "😉", "😍", "🥰", "😘",
  "😅", "😂", "🤣", "😇", "🤗", "🤔", "😐", "😌", "😔", "😢",
  "😭", "😮", "😴", "😎", "🥳", "😬", "🙄", "😡", "🤝", "🙏",
  "👍", "👎", "👌", "✌️", "👏", "🙌", "💪", "👋", "☝️", "👉",
  "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "💯", "✨", "🔥",
  "🎉", "🎁", "🛍️", "🛒", "📦", "🚚", "🏠", "📍", "📞", "📱",
  "💳", "💰", "🧾", "✅", "❌", "⚠️", "⏰", "⏳", "📅", "📝",
  "🔁", "🔔", "⭐", "🌟", "☀️", "🌙", "🌸", "🍀", "☕", "👀",
];

const cell = {
  border: "none",
  background: "transparent",
  cursor: "pointer",
  fontSize: 20,
  lineHeight: "28px",
  width: 32,
  height: 32,
  borderRadius: 6,
  padding: 0,
};

const EmojiPicker = ({ onPick, disabled }) => {
  const [open, setOpen] = useState(false);
  return (
    <Popover
      active={open}
      onClose={() => setOpen(false)}
      preferredPosition="above"
      activator={
        <Button
          icon={SmileyHappyMajor}
          variant="tertiary"
          disabled={disabled}
          accessibilityLabel={t("composer.emoji", "Add emoji")}
          onClick={() => setOpen((v) => !v)}
        />
      }
    >
      <Box padding="200" maxWidth="340px">
        <div style={{ display: "grid", gridTemplateColumns: "repeat(10, 32px)", gap: 2 }}>
          {EMOJI.map((emoji) => (
            <button
              key={emoji}
              type="button"
              style={cell}
              aria-label={emoji}
              onClick={() => {
                onPick(emoji);
                setOpen(false);
              }}
            >
              {emoji}
            </button>
          ))}
        </div>
      </Box>
    </Popover>
  );
};

export default EmojiPicker;
