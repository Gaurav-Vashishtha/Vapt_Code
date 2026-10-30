import React from "react";
import { Card, EmptyState as PolarisEmptyState } from "@shopify/polaris";

const IMAGE = "https://cdn.shopify.com/s/files/1/0262/4071/2726/files/emptystate-files.png";

/** Polaris empty state inside a card, the pattern the app's lists use. */
const EmptyState = ({ heading, children, action, secondaryAction, image, bare }) => {
  const content = (
    <PolarisEmptyState
      heading={heading}
      action={action}
      secondaryAction={secondaryAction}
      image={image || IMAGE}
    >
      {children}
    </PolarisEmptyState>
  );
  return bare ? content : <Card>{content}</Card>;
};

export default EmptyState;
