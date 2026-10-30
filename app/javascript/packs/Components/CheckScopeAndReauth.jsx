import React, { useEffect } from 'react';
// Removed: import {Redirect} from '@shopify/app-bridge/actions' // App Bridge v4 - use window.open instead

const CheckScopeAndReauth = ({ scopeRefreshUrl }) => {

  useEffect(() => {
    if (scopeRefreshUrl) {
      // App Bridge v4: Use window.open with "_top" for external redirects
      window.open(scopeRefreshUrl, "_top");
    }
  }, [scopeRefreshUrl]);

  return null
}

export default CheckScopeAndReauth;