import React, { useState } from 'react';
import {
  TextField, Icon, Button
} from '@shopify/polaris';
import { HideMinor, ViewMinor } from "@shopify/polaris-icons"

const RevealTextField = (props) => {
  const [isRevealed, setIsRevealed] = useState(false);

  const toggleReveal = () => {
    setIsRevealed(!isRevealed)
  };

  return (
    <TextField
      {...props}
      type={isRevealed ? 'text' : 'password'}
      connectedRight={
        isRevealed
        ? <Button icon={HideMinor} onClick={toggleReveal} />
        : <Button icon={ViewMinor} onClick={toggleReveal} />
      }
    />
  )
};

export default RevealTextField;