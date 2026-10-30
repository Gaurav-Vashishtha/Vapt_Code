import React, { useState } from "react";
import styled from "styled-components";

const Form = styled.form`
  display: flex;
  flex-direction: column;
  gap: 16px;
`;

const InputGroup = styled.div`
  display: flex;
  gap: 8px;
`;

const CountryCodeSelect = styled.select`
  width: 100px;
  padding: 10px;
  padding-left: 36px;
  border: 1px solid ${(props) => props.theme.border};
  border-radius: 4px;
  appearance: none;
  font-size: 14px;
`;

const FlagIcon = styled.div`
  position: absolute;
  left: 12px;
  top: 50%;
  transform: translateY(-50%);
`;

const Input = styled.input`
  flex: 1;
  padding: 10px;
  border: 1px solid ${(props) => props.theme.border};
  border-radius: 4px;
  font-size: 14px;
`;

const Checkbox = styled.label`
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
`;

const CheckboxInput = styled.input`
  width: 16px;
  height: 16px;
`;

// const Button = styled.button`
//   width: 100%;
//   padding: 12px;
//   background-color: ${(props) => props.theme.secondary};
//   color: #fff;
//   border: none;
//   border-radius: 4px;
//   font-size: 14px;
//   font-weight: 500;
//   cursor: pointer;
//   display: flex;
//   align-items: center;
//   justify-content: center;
//   gap: 8px;
// `;

const Button = styled.button`
  width: 100%;
  padding: 12px;
  background-color: ${(props) =>
    props.theme.primary}; /* Button background depends on primary */
  color: ${(props) =>
    props.theme.secondary}; /* Button text color depends on secondary */
  border: none;
  border-radius: 4px;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;

  &:hover {
    background-color: ${(props) =>
      props.theme.primaryDark}; /* Darker shade for hover */
    color: ${(props) => props.theme.secondary}; /* Text color stays the same */
  }

  &:disabled {
    background-color: ${(props) =>
      props.theme.border}; /* Use border color for disabled state */
    color: ${(props) =>
      props.theme.text}; /* Use text color for disabled state */
    cursor: not-allowed;
  }
`;

export default function ContactForm() {
  const [formData, setFormData] = useState({
    phone: "6295529286",
    email: "",
    receiveUpdates: true,
  });

  return (
    <Form onSubmit={(e) => e.preventDefault()}>
      <InputGroup>
        <div style={{ position: "relative", width: "100px" }}>
          <CountryCodeSelect>
            <option value="+91">+91</option>
          </CountryCodeSelect>
          <FlagIcon>🇮🇳</FlagIcon>
        </div>
        <Input
          type="tel"
          value={formData.phone}
          onChange={(e) =>
            setFormData((prev) => ({ ...prev, phone: e.target.value }))
          }
        />
      </InputGroup>

      <Input
        type="email"
        placeholder="Email address (optional)"
        value={formData.email}
        onChange={(e) =>
          setFormData((prev) => ({ ...prev, email: e.target.value }))
        }
      />

      <Checkbox>
        <CheckboxInput
          type="checkbox"
          checked={formData.receiveUpdates}
          onChange={(e) =>
            setFormData((prev) => ({
              ...prev,
              receiveUpdates: e.target.checked,
            }))
          }
        />
        <span>Send me offers and order updates</span>
      </Checkbox>

      <Button>
        Continue
        <span style={{ fontSize: "18px" }}>→</span>
      </Button>
    </Form>
  );
}
