import io, sys, json, os

REPO = os.getcwd()
JSX = REPO + "/app/javascript/packs/Components/PrepaidSettings.jsx"
EN = REPO + "/config/localeJson/en.json"

def read(p):
    with io.open(p, "r", encoding="utf-8") as f:
        return f.read()

def write(p, s):
    with io.open(p, "w", encoding="utf-8") as f:
        f.write(s)

def apply(content, old, new, label):
    n = content.count(old)
    if n != 1:
        raise SystemExit("ANCHOR FAIL [%s]: found %d occurrences (expected 1)" % (label, n))
    return content.replace(old, new, 1)

jsx = read(JSX)

if "testLink" in jsx or "test_payment_link" in jsx:
    print("JSX already patched, skipping jsx")
else:
    jsx = apply(
        jsx,
        "  const paymentSectionRef = useRef(null);",
        "  const [testLink, setTestLink] = useState({ loading: false, result: null });\n  const paymentSectionRef = useRef(null);",
        "jsx-state",
    )

    old2 = (
        "    setContextualBar(false);\n"
        "    setIsDirty(false);\n"
        "  }, [originalSetting, setSetting, setContextualBar]);"
    )
    new2 = old2 + (
        "\n\n"
        "  const handleTestPaymentLink = useCallback(async () => {\n"
        "    setTestLink({ loading: true, result: null });\n"
        "    try {\n"
        '      const response = await Api.post("/settings/test_payment_link", {\n'
        "        provider: setting.paymentProvider,\n"
        "        apiKey: setting.paymentProviderApiKey,\n"
        "        apiSecret: setting.paymentProviderApiSecret,\n"
        "      });\n"
        "      setTestLink({ loading: false, result: { ...response.data, ok: true } });\n"
        "    } catch (error) {\n"
        "      const data = error?.response?.data || {};\n"
        "      setTestLink({\n"
        "        loading: false,\n"
        "        result: {\n"
        "          ok: false,\n"
        "          message:\n"
        "            data.message ||\n"
        '            I18n.t("prepaid.payment.test_link.generic_error"),\n'
        "        },\n"
        "      });\n"
        "    }\n"
        "  }, [\n"
        "    setting?.paymentProvider,\n"
        "    setting?.paymentProviderApiKey,\n"
        "    setting?.paymentProviderApiSecret,\n"
        "  ]);\n\n"
        "  const handleDismissTestLink = useCallback(\n"
        "    () => setTestLink((s) => ({ ...s, result: null })),\n"
        "    [],\n"
        "  );"
    )
    jsx = apply(jsx, old2, new2, "jsx-handlers")

    jsx = apply(
        jsx,
        "    paymentErrors: errors = {},\n  }) => {",
        "    paymentErrors: errors = {},\n"
        "    testLink = { loading: false, result: null },\n"
        "    onTestLink,\n"
        "    onDismissTest,\n"
        "  }) => {",
        "jsx-signature",
    )

    old4 = (
        "          </>\n"
        "        )}\n"
        "      </BlockStack>\n"
        "    );\n"
        "  };\n\n"
        "  const DiscountSettings = ({ setting, handleSettingChange }) => ("
    )
    new4 = (
        "          </>\n"
        "        )}\n"
        "        <Divider />\n"
        '        <BlockStack gap="200">\n'
        '          <InlineStack gap="300" blockAlign="center" wrap>\n'
        "            <Button\n"
        "              onClick={onTestLink}\n"
        "              loading={testLink.loading}\n"
        "              disabled={testLink.loading}\n"
        "            >\n"
        '              {I18n.t("prepaid.payment.test_link.button")}\n'
        "            </Button>\n"
        '            <Text as="span" variant="bodySm" tone="subdued">\n'
        '              {I18n.t("prepaid.payment.test_link.hint")}\n'
        "            </Text>\n"
        "          </InlineStack>\n"
        "          {testLink.result && (\n"
        "            <Banner\n"
        '              tone={testLink.result.ok ? "success" : "critical"}\n'
        "              onDismiss={onDismissTest}\n"
        "              title={\n"
        "                testLink.result.ok\n"
        '                  ? I18n.t("prepaid.payment.test_link.success_title")\n'
        '                  : I18n.t("prepaid.payment.test_link.error_title")\n'
        "              }\n"
        "            >\n"
        '              <BlockStack gap="150">\n'
        "                <Text as=\"p\">{testLink.result.message}</Text>\n"
        "                {testLink.result.ok && testLink.result.link && (\n"
        "                  <Link url={testLink.result.link} external>\n"
        '                    {I18n.t("prepaid.payment.test_link.open_link")}\n'
        "                  </Link>\n"
        "                )}\n"
        "                {testLink.result.mode && (\n"
        '                  <Text as="p" variant="bodySm" tone="subdued">\n'
        '                    {I18n.t("prepaid.payment.test_link.mode", {\n'
        "                      mode: testLink.result.mode,\n"
        "                    })}\n"
        "                  </Text>\n"
        "                )}\n"
        "              </BlockStack>\n"
        "            </Banner>\n"
        "          )}\n"
        "        </BlockStack>\n"
        "      </BlockStack>\n"
        "    );\n"
        "  };\n\n"
        "  const DiscountSettings = ({ setting, handleSettingChange }) => ("
    )
    jsx = apply(jsx, old4, new4, "jsx-ui")

    old5 = (
        "                    {PaymentSettings({\n"
        "                      setting,\n"
        "                      handleSettingChange,\n"
        "                      paymentProviderOptions,\n"
        "                      paymentErrors,\n"
        "                    })}"
    )
    new5 = (
        "                    {PaymentSettings({\n"
        "                      setting,\n"
        "                      handleSettingChange,\n"
        "                      paymentProviderOptions,\n"
        "                      paymentErrors,\n"
        "                      testLink,\n"
        "                      onTestLink: handleTestPaymentLink,\n"
        "                      onDismissTest: handleDismissTestLink,\n"
        "                    })}"
    )
    jsx = apply(jsx, old5, new5, "jsx-callsite")
    write(JSX, jsx)
    print("JSX patched OK")

en_raw = read(EN)
if '"test_link"' in en_raw:
    print("en.json already patched, skipping")
else:
    old_en = (
        '      "validation": {\n'
        '        "api_key_required": "Required to enable the COD to Prepaid Conversion.",\n'
        '        "api_secret_required": "Required to enable the COD to Prepaid Conversion.",\n'
        '        "save_blocked": "Enter payment credentials above to save."\n'
        "      }\n"
        "    },"
    )
    new_en = (
        '      "validation": {\n'
        '        "api_key_required": "Required to enable the COD to Prepaid Conversion.",\n'
        '        "api_secret_required": "Required to enable the COD to Prepaid Conversion.",\n'
        '        "save_blocked": "Enter payment credentials above to save."\n'
        "      },\n"
        '      "test_link": {\n'
        '        "button": "Create test link",\n'
        '        "hint": "Generates a ₹1 payment link with your saved keys to confirm the setup works. Available for Razorpay, PayU and Cashfree.",\n'
        '        "success_title": "Configuration verified",\n'
        '        "error_title": "Couldn\'t create a test link",\n'
        '        "open_link": "Open test payment link",\n'
        '        "mode": "Environment: %{mode}",\n'
        '        "generic_error": "Something went wrong. Please check your credentials and try again."\n'
        "      }\n"
        "    },"
    )
    if en_raw.count(old_en) != 1:
        raise SystemExit("ANCHOR FAIL [en-validation]: found %d (expected 1)" % en_raw.count(old_en))
    en_new = en_raw.replace(old_en, new_en, 1)
    json.loads(en_new)
    write(EN, en_new)
    print("en.json patched OK")

print("DONE")
