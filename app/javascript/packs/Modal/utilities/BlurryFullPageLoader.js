import React, { useEffect, useState } from "react";
import styled, { keyframes } from "styled-components";

const BlurryOverlay = styled.div`
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background-color: rgba(255, 255, 255, 0.5);
  backdrop-filter: blur(8px);
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 9999;
`;

const spin = keyframes`
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
`;

const LoaderContainer = styled.div`
  display: flex;
  flex-direction: column;
  align-items: center;
`;

const Spinner = styled.div`
  width: 50px;
  height: 50px;
  border: 5px solid #f3f3f3;
  border-top: 5px solid #3498db;
  border-radius: 50%;
  animation: ${spin} 1s linear infinite;
`;

const Message = styled.p`
  margin-top: 20px;
  font-size: 18px;
  color: #333;
  text-align: center;
`;

const BlurryFullPageLoader = ({ message }) => {
  return (
    <BlurryOverlay>
      <LoaderContainer>
        <Spinner />
        <Message>{message}</Message>
      </LoaderContainer>
    </BlurryOverlay>
  );
};

export default BlurryFullPageLoader;
