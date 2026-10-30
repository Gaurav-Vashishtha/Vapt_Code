import React, { useEffect, useCallback } from "react";
import ReactDOM from "react-dom";
import "./css/ModalContainer.css";

const ModalContainer = ({ children, onClose }) => {
  const modalRoot = document.getElementById("modal-root") || document.body;

  // Handle Esc key press to close modal
  const handleKeyDown = useCallback(
    (event) => {
      if (event.key === "Escape" && onClose) {
        onClose();
      }
    },
    [onClose]
  );

  // Handle backdrop click to close modal
  const handleBackdropClick = useCallback(
    (event) => {
      if (event.target === event.currentTarget && onClose) {
        onClose();
      }
    },
    [onClose]
  );

  // Add event listener for Esc key
  useEffect(() => {
    if (onClose) {
      document.addEventListener("keydown", handleKeyDown);
      // Prevent body scroll when modal is open
      document.body.style.overflow = "hidden";
    }

    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = "unset";
    };
  }, [handleKeyDown, onClose]);

  // Render the modal into a portal
  return ReactDOM.createPortal(
    <div className="codk-modal-overlay" onClick={handleBackdropClick}>
      {children}
    </div>,
    modalRoot
  );
};

export default ModalContainer;
