import React from "react";
import styled from "styled-components";
import { ArrowLeft } from "lucide-react";

const StyledButton = styled.button`
  color: ${(props) => (props.disabled ? "#9CA3AF" : "#4B5563")};
  background: none;
  border: none;
  cursor: ${(props) => (props.disabled ? "not-allowed" : "pointer")};
  opacity: ${(props) => (props.disabled ? 0.5 : 1)};
  transition: color 0.2s;

  &:hover:not(:disabled) {
    color: #dc2626;
  }

  &:focus {
    outline: none;
  }
`;

export default function BackButton({ onBack, disabled = false }) {
  return (
    <StyledButton onClick={onBack} disabled={disabled} aria-label="Go back">
      <ArrowLeft size={24} />
    </StyledButton>
  );
}
