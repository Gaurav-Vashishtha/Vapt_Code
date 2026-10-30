import React from "react";
import styled from "styled-components";
import { Percent } from "lucide-react";

// CouponsSection Component
const CouponsSection = ({ theme }) => (
  <StyledCouponsSection>
    <StyledCouponsHeader>
      <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
        <CouponIcon>
          <Percent size={18} />
        </CouponIcon>
        <span>Coupons and offers</span>
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
        <span>3 coupons and offers</span>
        <span>›</span>
      </div>
    </StyledCouponsHeader>
  </StyledCouponsSection>
);

export default CouponsSection;
// StyledCouponsSection
const StyledCouponsSection = styled.div`
  background-color: rgba(255, 255, 255, 0.1);
  border-radius: 8px;
  padding: 16px;
  margin-bottom: 24px;
`;

// StyledCouponsHeader
const StyledCouponsHeader = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: center;
`;

const CouponIcon = styled.div`
  width: 30px;
  height: 24px;
  background-color: #fff;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: ${(props) => props.theme.primary};
`;
