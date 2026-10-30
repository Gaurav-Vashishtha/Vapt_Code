import React from "react";
import styled, { keyframes, css } from "styled-components";
import { ThreeDots } from "react-loader-spinner";
<ThreeDots
  visible={true}
  height="80"
  width="80"
  color="#4fa94d"
  radius="9"
  ariaLabel="three-dots-loading"
  wrapperStyle={{}}
  wrapperClass=""
/>;

const SpinnerWrapper = styled.div`
  display: flex;
  align-items: center;
  justify-content: center;
  margin-right: 8px;
`;
// Styled button with conditional styling

const Button = styled.button`
  display: flex;
  align-items: center;
  justify-content: center;
  width: ${({ $width }) => $width || "100%"};
  padding: 12px 24px;
  font-size: 16px;
  font-weight: 600;
  border: none;
  border-radius: 10px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08), 0 4px 16px rgba(0, 0, 0, 0.06);

  color: ${({ $color }) => $color || "#ffffff"};
  background-color: ${({ $background }) => $background || "#0e0e0e"};
  cursor: pointer;
  transition: background-color 0.2s ease;

  &:hover:not(:disabled) {
    background-color: ${({ $hoverBackground, $background }) =>
      $hoverBackground || $background || "#1a1a1a"};
  }

  &:active:not(:disabled) {
    background-color: ${({ $hoverBackground, $background }) =>
      $hoverBackground || $background || "#000000"};
  }

  &:disabled {
    background-color: ${({ $background }) => $background || "#0e0e0e"};
    cursor: not-allowed;
    opacity: 0.6;
  }

  ${({ $loading }) =>
    $loading &&
    css`
      pointer-events: none;
      opacity: 1; // Keep full visibility when loading
    `}
`;

const CodkingButton = ({
  children = "Continue",
  onClick,
  loading = false,
  disabled = false,
  background,
  hoverBackground,
  color,
  width,
  style,
}) => {
  return (
    <Button
      onClick={onClick}
      disabled={disabled || loading}
      $loading={loading}
      $color={color}
      $background={background}
      $hoverBackground={hoverBackground}
      $width={width}
      style={style}
    >
      {loading ? (
        <SpinnerWrapper>
          <ThreeDots
            visible={true}
            height="25"
            width="25"
            color="#ffffff"
            radius="9"
            ariaLabel="three-dots-loading"
          />
        </SpinnerWrapper>
      ) : (
        children
      )}
    </Button>
  );
};

export default CodkingButton;
