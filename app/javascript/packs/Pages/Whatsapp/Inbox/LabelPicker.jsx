import React, { useState } from "react";
import { Box, Button, OptionList, Popover, Text } from "@shopify/polaris";
import { t } from "./format";

const LabelPicker = ({ labels = [], selected = [], onChange, disabled }) => {
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState([]);

  const toggle = () => {
    if (open) {
      close();
      return;
    }
    setDraft(selected.map(String));
    setOpen(true);
  };

  const close = () => {
    setOpen(false);
    const before = selected.map(String).sort().join(",");
    const after = [...draft].sort().join(",");
    if (before !== after) onChange(draft.map(Number));
  };

  return (
    <Popover
      active={open}
      onClose={close}
      preferredAlignment="right"
      activator={
        <Button disclosure onClick={toggle} disabled={disabled}>
          {t("header.labels", "Labels")}
        </Button>
      }
    >
      {labels.length === 0 ? (
        <Box padding="300" maxWidth="280px">
          <Text as="p" tone="subdued">
            {t("header.no_labels", "No labels yet. Add them in inbox settings.")}
          </Text>
        </Box>
      ) : (
        <OptionList
          allowMultiple
          options={labels.map((label) => ({ value: String(label.id), label: label.name }))}
          selected={draft}
          onChange={setDraft}
        />
      )}
    </Popover>
  );
};

export default LabelPicker;
