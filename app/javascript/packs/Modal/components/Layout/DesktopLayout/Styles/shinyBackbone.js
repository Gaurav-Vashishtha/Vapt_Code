import { css } from "styled-components";

// Shiny backbone effect that can be added to any styled component
export const shinyBackboneEffect = css`
  position: relative;
  overflow: hidden;

  /* Dramatic backbone shimmer effect */
  background: linear-gradient(
    90deg,
    currentColor 0%,
    currentColor 20%,
    #ffffff 40%,
    #ffffff 60%,
    currentColor 80%,
    currentColor 100%
  );
  background-size: 300% 100%;
  animation: backboneShine 1.5s linear infinite;

  /* Bright metallic shine overlay */
  &::before {
    content: "";
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: linear-gradient(
      135deg,
      transparent 0%,
      transparent 30%,
      rgba(255, 255, 255, 0.9) 45%,
      rgba(255, 255, 255, 1) 50%,
      rgba(255, 255, 255, 0.9) 55%,
      transparent 70%,
      transparent 100%
    );
    border-radius: inherit;
    animation: diagonalShine 2s ease-in-out infinite;
    pointer-events: none;
  }

  /* Extra glow effect */
  &::after {
    content: "";
    position: absolute;
    top: -2px;
    left: 0;
    right: 0;
    bottom: 0;
    background: linear-gradient(
      to right,
      transparent 0%,
      rgba(255, 255, 255, 0.6) 50%,
      transparent 100%
    );
    border-radius: inherit;
    animation: topGlow 2.5s ease-in-out infinite alternate;
    pointer-events: none;
  }

  @keyframes backboneShine {
    0% {
      background-position: -300% 0;
    }
    100% {
      background-position: 300% 0;
    }
  }

  @keyframes diagonalShine {
    0% {
      transform: translateX(-100%) skewX(-15deg);
      opacity: 0;
    }
    50% {
      opacity: 1;
    }
    100% {
      transform: translateX(100%) skewX(-15deg);
      opacity: 0;
    }
  }

  @keyframes topGlow {
    0% {
      opacity: 0.3;
      transform: scaleX(0.8);
    }
    100% {
      opacity: 0.8;
      transform: scaleX(1.2);
    }
  }
`;

// Alternative version with customizable base color
export const shinyBackboneEffectWithColor = (baseColor = "#a5a0a0") => css`
  position: relative;
  overflow: hidden;

  /* Dramatic backbone shimmer effect */
  background: linear-gradient(
    90deg,
    ${baseColor} 0%,
    ${baseColor} 20%,
    #ffffff 40%,
    #ffffff 60%,
    ${baseColor} 80%,
    ${baseColor} 100%
  );
  background-size: 300% 100%;
  animation: backboneShine 1.5s linear infinite;

  /* Bright metallic shine overlay */
  &::before {
    content: "";
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: linear-gradient(
      135deg,
      transparent 0%,
      transparent 30%,
      rgba(255, 255, 255, 0.9) 45%,
      rgba(255, 255, 255, 1) 50%,
      rgba(255, 255, 255, 0.9) 55%,
      transparent 70%,
      transparent 100%
    );
    border-radius: inherit;
    animation: diagonalShine 2s ease-in-out infinite;
    pointer-events: none;
  }

  /* Extra glow effect */
  &::after {
    content: "";
    position: absolute;
    top: -2px;
    left: 0;
    right: 0;
    bottom: 0;
    background: linear-gradient(
      to right,
      transparent 0%,
      rgba(255, 255, 255, 0.6) 50%,
      transparent 100%
    );
    border-radius: inherit;
    animation: topGlow 2.5s ease-in-out infinite alternate;
    pointer-events: none;
  }

  @keyframes backboneShine {
    0% {
      background-position: -300% 0;
    }
    100% {
      background-position: 300% 0;
    }
  }

  @keyframes diagonalShine {
    0% {
      transform: translateX(-100%) skewX(-15deg);
      opacity: 0;
    }
    50% {
      opacity: 1;
    }
    100% {
      transform: translateX(100%) skewX(-15deg);
      opacity: 0;
    }
  }

  @keyframes topGlow {
    0% {
      opacity: 0.3;
      transform: scaleX(0.8);
    }
    100% {
      opacity: 0.8;
      transform: scaleX(1.2);
    }
  }
`;

export const shinyBadgeEffectWithColor = (baseColor = "#d1fae5") => css`
  position: relative;
  overflow: hidden;
  background-color: ${baseColor};
  color: inherit;

  /* Subtle shimmer background (barely visible) */
  background-image: linear-gradient(
    90deg,
    ${baseColor},
    ${baseColor},
    #ffffff33,
    ${baseColor}
  );
  background-size: 200% 100%;
  animation: badgeShine 2.5s linear infinite;

  &::before {
    content: "";
    position: absolute;
    top: 0;
    left: -50%;
    height: 100%;
    width: 200%;
    background: linear-gradient(
      120deg,
      transparent 0%,
      rgba(255, 255, 255, 0.35) 50%,
      transparent 100%
    );
    animation: badgeGlint 3s ease-in-out infinite;
    pointer-events: none;
  }

  @keyframes badgeShine {
    0% {
      background-position: 200% 0;
    }
    100% {
      background-position: -200% 0;
    }
  }

  @keyframes badgeGlint {
    0% {
      transform: translateX(-100%) skewX(-10deg);
      opacity: 0;
    }
    50% {
      opacity: 0.3;
    }
    100% {
      transform: translateX(100%) skewX(-10deg);
      opacity: 0;
    }
  }
`;
