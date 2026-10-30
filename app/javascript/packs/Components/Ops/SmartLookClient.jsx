import React, { useEffect } from 'react'
import smartlook from 'smartlook-client'

if (process.env.NODE_ENV === 'production') {
  smartlook.init(process.env.SMARTLOOK_KEY)
}

const SmartLookClient = ({ shop, plan }) => {
  useEffect(() => {
    if (shop?.shopify_domain &&
        process.env.NODE_ENV === 'production') {
      smartlook.identify(shop.shopify_domain, {
        name: shop.shop_owner,
        email: shop.owner_email,
        package: plan.name,
        currency: 'USD',
        cost: Number(plan.price)
      });
    }
    return () => {
      smartlook.anonymize();
    };
  }, [shop.shopify_domain, process.env.NODE_ENV]);
  return null;
};

export default SmartLookClient;
