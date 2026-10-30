import React, { useState, useEffect } from "react";
import {
  Button,
  Modal,
  TextField,
  FormLayout,
  Select,
  TextContainer,
  Banner,
  Card,
  Layout,
  Text,
} from "@shopify/polaris";
import Api from "../Services/Api";
import I118n from "../i18n-lang";
import I18n from "../i18n-lang";

const CallbackRequest = () => {
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [canRequest, setCanRequest] = useState(true);
  const [formData, setFormData] = useState({
    name: "",
    phone_number: "",
    email: "",
    preferred_time: "",
    timezone: "Asia/Kolkata",
    notes: "",
  });
  const [errors, setErrors] = useState({});
  const [successMessage, setSuccessMessage] = useState("");

  const timezones = [
    { label: I118n.t("callback.timezone_options.utc"), value: "UTC" },
    {
      label: I118n.t("callback.timezone_options.et"),
      value: "America/New_York",
    },
    {
      label: I118n.t("callback.timezone_options.ct"),
      value: "America/Chicago",
    },
    { label: I118n.t("callback.timezone_options.mt"), value: "America/Denver" },
    {
      label: I118n.t("callback.timezone_options.pt"),
      value: "America/Los_Angeles",
    },
    { label: I118n.t("callback.timezone_options.ist"), value: "Asia/Kolkata" },
    { label: I118n.t("callback.timezone_options.gmt"), value: "Europe/London" },
    { label: I118n.t("callback.timezone_options.cet"), value: "Europe/Berlin" },
    {
      label: I118n.t("callback.timezone_options.aedt"),
      value: "Australia/Sydney",
    },
  ];

  useEffect(() => {
    checkCallbackAvailability();
  }, []);

  const checkCallbackAvailability = async () => {
    try {
      const response = await Api.get(
        "/api/callback_requests/check_availability",
      );
      if (response.data) {
        setCanRequest(response.data.canRequest);
      }
    } catch (error) {
      console.error("Failed to check callback availability:", error);
    }
  };

  const validateForm = () => {
    const newErrors = {};

    if (!formData.name.trim()) {
      newErrors.name = I118n.t("callback.errors.name_required");
    }

    if (!formData.phone_number.trim()) {
      newErrors.phone_number = I118n.t("callback.errors.phone_required");
    }

    if (!formData.email.trim()) {
      newErrors.email = I118n.t("callback.errors.email_required");
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(formData.email)) {
      newErrors.email = I118n.t("callback.errors.email_invalid");
    }

    if (!formData.preferred_time.trim()) {
      newErrors.preferred_time = I118n.t("callback.errors.time_required");
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async () => {
    if (!validateForm()) return;

    setIsSubmitting(true);
    setErrors({});

    try {
      const response = await Api.post("/api/callback_requests", {
        callback_request: formData,
      });

      if (response.data) {
        setSuccessMessage(I118n.t("callback.success_message"));
        setCanRequest(false);

        setTimeout(() => {
          setIsModalOpen(false);
          resetForm();
        }, 3000);
      } else {
        setErrors({ general: I118n.t("callback.error_generic") });
      }
    } catch (error) {
      console.error("Error submitting callback request:", error);
      setErrors({ general: I118n.t("callback.error_generic") });
    } finally {
      setIsSubmitting(false);
    }
  };

  const resetForm = () => {
    setFormData({
      name: "",
      phone_number: "",
      email: "",
      preferred_time: "",
      timezone: "Asia/Kolkata",
      notes: "",
    });
    setErrors({});
    setSuccessMessage("");
  };

  const handleModalClose = () => {
    setIsModalOpen(false);
    resetForm();
  };

  return (
    <React.Fragment>
      <Card sectioned>
        <Layout>
          <Layout.Section>
            <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
              <div style={{ fontSize: "20px" }}>🛠️</div>
              <div>
                <Text variant="headingSm" as="h3">
                  {I118n.t("callback.need_help")}
                </Text>
                <Text variant="bodySm" color="subdued">
                  {I118n.t("callback.learn_how_to_configure")}
                </Text>
              </div>
            </div>
          </Layout.Section>
          <Layout.Section>
            <Button
              onClick={() => setIsModalOpen(true)}
              disabled={!canRequest}
              fullWidth
              variant="primary"
            >
              {I118n.t("callback.request_button")}
            </Button>
          </Layout.Section>
        </Layout>
      </Card>

      <Modal
        open={isModalOpen}
        onClose={handleModalClose}
        title={I118n.t("callback.modal_title")}
      >
        <Modal.Section>
          {successMessage && (
            <Banner status="success" onDismiss={() => setSuccessMessage("")}>
              {successMessage}
            </Banner>
          )}

          {errors.general && (
            <Banner status="critical" onDismiss={() => setErrors({})}>
              {errors.general}
            </Banner>
          )}

          <FormLayout>
            <TextField
              label={I118n.t("callback.fields.name")}
              value={formData.name}
              onChange={(value) => setFormData({ ...formData, name: value })}
              error={errors.name}
              autoComplete="name"
            />

            <TextField
              label={I118n.t("callback.fields.phone")}
              value={formData.phone_number}
              onChange={(value) =>
                setFormData({ ...formData, phone_number: value })
              }
              error={errors.phone_number}
              helpText={I118n.t("callback.phone_help_india")}
              type="tel"
              autoComplete="tel"
            />

            <TextField
              label={I118n.t("callback.fields.email")}
              value={formData.email}
              onChange={(value) => setFormData({ ...formData, email: value })}
              error={errors.email}
              type="email"
              autoComplete="email"
            />

            <TextField
              label={I118n.t("callback.fields.preferred_time")}
              value={formData.preferred_time}
              onChange={(value) =>
                setFormData({ ...formData, preferred_time: value })
              }
              error={errors.preferred_time}
              helpText={I118n.t("callback.time_help")}
              placeholder={I18n.t("callback_request.e_g_2_00_pm_4")}
            />

            <Select
              label={I118n.t("callback.fields.timezone")}
              options={timezones}
              value={formData.timezone}
              onChange={(value) =>
                setFormData({ ...formData, timezone: value })
              }
            />

            <TextField
              label={I118n.t("callback.fields.notes")}
              value={formData.notes}
              onChange={(value) => setFormData({ ...formData, notes: value })}
              multiline={4}
              helpText={I118n.t("callback.notes_help")}
              maxLength={1000}
              showCharacterCount
            />
          </FormLayout>

          <div style={{ marginTop: "16px" }}>
            <TextContainer>
              <Text variant="bodySm" color="subdued">
                {I118n.t("callback.disclaimer")}
              </Text>
            </TextContainer>
          </div>

          <div
            style={{
              display: "flex",
              justifyContent: "flex-end",
              gap: "8px",
              marginTop: "16px",
              paddingBottom: "60px",
            }}
          >
            <Button onClick={handleModalClose} disabled={isSubmitting}>
              {I118n.t("callback.cancel")}
            </Button>
            <Button
              variant="primary"
              onClick={handleSubmit}
              loading={isSubmitting}
              disabled={isSubmitting}
            >
              {I118n.t("callback.submit")}
            </Button>
          </div>
        </Modal.Section>
      </Modal>
    </React.Fragment>
  );
};

export default CallbackRequest;
