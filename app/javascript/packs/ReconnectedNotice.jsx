import React, { useState } from "react";
import { Modal, Text } from "@shopify/polaris";

const ReconnectedNotice = () => {
  const [open, setOpen] = useState(true);
  return (
    <Modal
      open={open}
      onClose={() => setOpen(false)}
      title="Your store is reconnected"
      primaryAction={{ content: "Got it", onAction: () => setOpen(false) }}
    >
      <Modal.Section>
        <Text as="p">
          COD King is connected to your store again. Your COD confirmations are
          running normally, and you don't need to do anything else.
        </Text>
      </Modal.Section>
    </Modal>
  );
};

export default ReconnectedNotice;
