import React, { useState, useEffect, useContext } from "react";
import useApi from "../Hooks/useApi";
import { Card, TextField, Button, Banner } from "@shopify/polaris";
import { StoreContext } from "../Context/Store";
import I18n from "../i18n-lang";

const TestOtp = () => {
  const {
    setting: [{ template, locked }],
    number: [number, setNumber],
    testCount: [testCount, setTestCount],
  } = useContext(StoreContext);

  const [localError, setLocalError] = useState(false);

  const [{ data, loading, error }, send] = useApi(
    {
      url: "/settings/test_otp",
      method: "POST",
      data: {
        customer_number: number,
        template,
      },
    },
    { manual: true }
  );

  const sendTestOtp = () => {
    if (testCount > 0 && number.length > 0) {
      send().then((resp) => {
        if (resp.status === 200) {
          setTestCount((c) => c - 1);
        }
      });
    }
  };

  useEffect(() => {
    if (template && testCount < 1) {
      setTestCount(1);
    }
  }, [template]);

  const onNumberChange = (number) => {
    setNumber(number)
    if (!number.startsWith('+')) {
      setLocalError(true)
    } else if(localError) {
      setLocalError(false);
    }
  };

  return (
    <Card title={I18n.t("admin.test_sms")} sectioned>
      {data?.sid && <Banner status='info'>
          {I18n.t("admin.sms_sent_check_mobile")}
        </Banner>
      }
      <TextField
        label={I18n.t("admin.enter_test_number")}
        value={number}
        onChange={onNumberChange}
        placeholder={I18n.t("test_otp.xx_xxxxxxxxxx")}
        maxLength={16}
        minLength={8}
        inputMode="numeric"
        error={localError ? I18n.t("admin.enter_country_code") : error?.response?.data?.error}
        helpText={
          I18n.t("admin.number_cc_example", {
            number: '+91 9654XXXXXX'
          })
        }
        connectedRight={
          <Button onClick={sendTestOtp} loading={loading} disabled={locked}>
            {I18n.t("admin.send_sms")}
          </Button>
        }
      />
    </Card>
  );
};

export default TestOtp;
