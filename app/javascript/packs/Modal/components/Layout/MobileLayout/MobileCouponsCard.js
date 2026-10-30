import React, { useState } from "react";
import styled from "styled-components";

const CouponsCard = ({ theme }) => (
  <StyledCouponsCard theme={theme}>
    <CouponsHeader>
      <CouponsLeft>
        <CouponIcon>%</CouponIcon>
        <CouponsTitle>Coupons and offers</CouponsTitle>
      </CouponsLeft>
      <CouponsRight>
        <CouponsCount>3 coupons and offers</CouponsCount>
        <Arrow>&gt;</Arrow>
      </CouponsRight>
    </CouponsHeader>
  </StyledCouponsCard>
);

export default CouponsCard;
// Styled Coupons Card
const StyledCouponsCard = styled.div`
  background-color: ${(props) => props.theme.cardBg};
  border-radius: 12px;
  padding: 16px;
  margin-bottom: 24px;
`;

const CouponsHeader = styled.div`
  display: flex;
  align-items: center;
  justify-content: space-between;
`;

const CouponsLeft = styled.div`
  display: flex;
  align-items: center;
  gap: 12px;
`;

const CouponIcon = styled.div`
  width: 32px;
  height: 32px;
  background-color: #22c55e;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  font-size: 16px;
`;

const CouponsTitle = styled.span`
  font-size: 16px;
`;

const CouponsRight = styled.div`
  display: flex;
  align-items: center;
  gap: 8px;
`;

const CouponsCount = styled.span`
  color: #666;
`;
const Arrow = styled.span`
  color: #666;
`;
