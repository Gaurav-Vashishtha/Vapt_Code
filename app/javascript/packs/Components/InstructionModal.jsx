import React, { useState, useCallback, useEffect } from "react";
import { Modal, Button } from "@shopify/polaris";
import { InstructionPage } from "./InstructionPage";
import I18n from "../i18n-lang";

export function InstructionModal() {
  const [active, setActive] = useState(false);

  const handleChange = useCallback(() => setActive(!active), [active]);

  // Handle Esc key press to close modal
  const handleKeyDown = useCallback(
    (event) => {
      if (event.key === "Escape" && active) {
        handleChange();
      }
    },
    [active, handleChange]
  );

  // Add event listener for Esc key
  useEffect(() => {
    if (active) {
      document.addEventListener("keydown", handleKeyDown);
      // Prevent body scroll when modal is open
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "unset";
    }

    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = "unset";
    };
  }, [active, handleKeyDown]);

  const activator = (
    <Button onClick={handleChange} variant="primary">
      {I18n.t("instruction_modal.login_setup_instructions")}
    </Button>
  );

  return (
    <div>
      {activator}
      <Modal
        open={active}
        onClose={handleChange}
        title={I18n.t("instruction_modal.login_otp_title")}
        large
        backdrop={true}
      >
        <Modal.Section>
          <InstructionPage />
        </Modal.Section>
      </Modal>
    </div>
  );
}
