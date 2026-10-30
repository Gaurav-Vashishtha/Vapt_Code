import React, { useCallback, useContext } from 'react'
import { Frame, Page, Card, Tabs } from '@shopify/polaris';
import { StoreContext } from '../../Context/Store';
import Step1 from './Step1';
import Step2 from './Step2';
import I18n from "../../i18n-lang";

const tabs = [{
  id: 'codConfirmion',
  get content() {
      return I18n.t("tabs.wish_connection");
    },
  accessibilityLabel: 'Wish Connection',
  panelID: 'codConfirmion',
}, {
  id: 'importProducts',
  get content() {
      return I18n.t("tabs.import_products");
    },
  accessibilityLabel: 'Import Products',
  panelID: 'importProducts',
}];

const TabsList = [
  <Step1 />,
  <Step2 />,
];

const OnboardingTabs = () => {
  const {
    tab: [tab, setTab],
  } = useContext(StoreContext);

  const handleTabChange = useCallback((index) => setTab(index), []);

  return (
    <Frame>
      <Page fullWidth>
        <Card>
          <Tabs tabs={tabs} selected={tab} onSelect={handleTabChange}>
              { TabsList[tab] }
          </Tabs>
        </Card>
      </Page>
    </Frame>
  );
}

export default OnboardingTabs;
