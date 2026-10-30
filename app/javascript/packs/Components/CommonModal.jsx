// import React, { useRef, useEffect, forwardRef } from "react";
// import { Modal } from "@shopify/polaris";

// const CommonModal = forwardRef(
//   (
//     { open, onClose, title, primaryActionContent, primaryAction, children },
//     ref
//   ) => {
//     const modalRef = useRef(null);

//     useEffect(() => {
//       const handleKeyDown = (e) => {
//         if (e.key === "x" || e.key === "X") {
//           onClose(); // Close modal on 'x' key press
//         }
//       };

//       if (open) {
//         document.addEventListener("keydown", handleKeyDown);
//       }

//       return () => {
//         document.removeEventListener("keydown", handleKeyDown);
//       };
//     }, [open, onClose]);

//     useEffect(() => {
//       if (open) {
//         modalRef.current && modalRef.current.focus();
//       }
//     }, [open]);

//     return (
//       <Modal
//         open={open}
//         onClose={onClose}
//         title={title}
//         primaryAction={{
//           content: primaryActionContent,
//           onAction: primaryAction,
//         }}
//       >
//         <Modal.Section>
//           <div ref={modalRef} tabIndex={-1}>
//             {children}
//           </div>
//         </Modal.Section>
//       </Modal>
//     );
//   }
// );

// export default CommonModal;

import React, { useRef, useEffect, forwardRef } from "react";
import { Modal } from "@shopify/polaris";
import "./CommonModal.css"; // We'll define the backdrop CSS here

const CommonModal = forwardRef(
  (
    { open, onClose, title, primaryActionContent, primaryAction, children },
    ref
  ) => {
    const modalRef = useRef(null);

    useEffect(() => {
      const handleKeyDown = (e) => {
        // Close modal on Esc key (standard) or X key (custom)
        if (e.key === "Escape" || e.key === "x" || e.key === "X") {
          onClose();
        }
      };

      if (open) {
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
    }, [open, onClose]);

    useEffect(() => {
      if (open && modalRef.current) {
        modalRef.current.focus();
      }
    }, [open]);

    return (
      <>
        {open && <div className="custom-backdrop" onClick={onClose} />}
        <Modal
          open={open}
          onClose={onClose}
          title={title}
          primaryAction={{
            content: primaryActionContent,
            onAction: primaryAction,
          }}
          backdrop={true}
        >
          <Modal.Section>
            <div ref={modalRef} tabIndex={-1}>
              {children}
            </div>
          </Modal.Section>
        </Modal>
      </>
    );
  }
);

export default CommonModal;
