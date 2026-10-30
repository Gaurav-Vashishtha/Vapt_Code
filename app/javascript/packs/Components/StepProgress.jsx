// import React from "react";
// import styled, { keyframes } from "styled-components";

// const StepContainer = styled.div`
//   display: flex;
//   justify-content: space-between;
//   align-items: center;
//   width: 100%;
//   padding: 1.5rem 1rem;
//   border-top: 1px solid #e5e7eb;
// `;

// const StepItem = styled.div`
//   flex: 1;
//   display: flex;
//   flex-direction: column;
//   align-items: center;
//   position: relative;
// `;

// const bounceIn = keyframes`
//   0% { transform: scale(0); opacity: 0; }
//   60% { transform: scale(1.1); opacity: 1; }
//   100% { transform: scale(1); }
// `;

// const StepCircle = styled.div`
//   width: 2rem;
//   height: 2rem;
//   border-radius: 9999px;
//   background-color: ${(props) =>
//     props.active || props.completed ? "#2563eb" : "#d1d5db"};
//   border: 1px solid
//     ${(props) => (props.active || props.completed ? "#2563eb" : "#d1d5db")};
//   color: white;
//   font-size: 14px;
//   font-weight: 600;
//   display: flex;
//   align-items: center;
//   justify-content: center;
//   z-index: 10;
//   animation: ${bounceIn} 0.4s ease-in-out;
// `;

// const StepLabel = styled.span`
//   margin-top: 0.5rem;
//   font-size: 14px;
//   text-align: center;
//   font-weight: ${(props) => (props.active ? "600" : "400")};
//   color: ${(props) => (props.active ? "#111827" : "#6b7280")};
// `;

// const StepLine = styled.div`
//   position: absolute;
//   top: 1rem;
//   left: 50%;
//   width: 100%;
//   height: 1px;
//   background-color: #d1d5db;
//   transform: translateX(1rem);
//   z-index: 0;
// `;

// const StepProgress = ({ steps = [], currentStep = 0 }) => {
//   if (!Array.isArray(steps) || steps.length === 0) {
//     return (
//       <div style={{ textAlign: "center", color: "#9ca3af" }}>
//         No steps provided
//       </div>
//     );
//   }

//   return (
//     <StepContainer>
//       {steps.map((step, index) => {
//         const isCompleted = index < currentStep;
//         const isActive = index === currentStep;

//         return (
//           <StepItem key={index}>
//             <StepCircle active={isActive} completed={isCompleted}>
//               {isCompleted ? "✔" : index + 1}
//             </StepCircle>
//             <StepLabel active={isActive}>{step}</StepLabel>
//             {index !== steps.length - 1 && <StepLine />}
//           </StepItem>
//         );
//       })}
//     </StepContainer>
//   );
// };

// export default StepProgress;
import React from "react";
import styled, { keyframes } from "styled-components";
import I18n from "../i18n-lang";

const StepContainer = styled.div`
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  align-items: flex-start;
  width: 100%;
  padding: 1.5rem 1rem;
  // border-top: 1px solid #e5e7eb;
  gap: 1rem;

  @media (max-width: 600px) {
    justify-content: center;
  }
`;

const StepItem = styled.div`
  flex: 1 1 100px;
  min-width: 80px;
  display: flex;
  flex-direction: column;
  align-items: center;
  position: relative;
  text-align: center;
`;

const bounceIn = keyframes`
  0% { transform: scale(0); opacity: 0; }
  60% { transform: scale(1.1); opacity: 1; }
  100% { transform: scale(1); }
`;

const StepCircle = styled.div`
  width: 2rem;
  height: 2rem;
  border-radius: 9999px;
  background-color: ${(props) => (props.active ? "#10b981" : "transparent")};
  border: 2px solid ${(props) => (props.active ? "#10b981" : "#d1d5db")};
  color: ${(props) => (props.active ? "white" : "#111827")};
  font-size: 14px;
  font-weight: 600;
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 10;
  animation: ${bounceIn} 0.4s ease-in-out;
`;

const StepLabel = styled.span`
  margin-top: 0.5rem;
  font-size: 14px;
  font-weight: ${(props) => (props.active ? "600" : "400")};
  color: ${(props) => (props.active ? "#10b981" : "#6b7280")};
  word-break: break-word;

  @media (max-width: 600px) {
    font-size: 12px;
  }
`;
// #6b7280
const StepLine = styled.div`
  position: absolute;
  top: 1rem;
  left: 50%;
  width: 100%;
  height: 1px;
  background-color: #d1d5db;
  transform: translateX(1rem);
  z-index: 0;

  @media (max-width: 600px) {
    display: none;
  }
`;

const StepProgress = ({ steps = [], currentStep = 0 }) => {
  if (!Array.isArray(steps) || steps.length === 0) {
    return (
      <div style={{ textAlign: "center", color: "#9ca3af" }}>
        {I18n.t("step_progress.no_steps_provided")}
      </div>
    );
  }

  return (
    <StepContainer>
      {steps.map((step, index) => {
        const isActive = index === currentStep;

        return (
          <StepItem key={index}>
            <StepCircle active={isActive}>{index + 1}</StepCircle>
            <StepLabel active={isActive}>{step}</StepLabel>
            {index !== steps.length - 1 && <StepLine />}
          </StepItem>
        );
      })}
    </StepContainer>
  );
};

export default StepProgress;
