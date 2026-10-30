import React, { useEffect } from "react";

const Clarity = ({ shop, plan }) => {
  useEffect(() => {
    (function (c, l, a, r, i, t, y) {
      c[a] =
        c[a] ||
        function () {
          (c[a].q = c[a].q || []).push(arguments);
        };
      t = l.createElement(r);
      t.async = 1;
      t.src = "https://www.clarity.ms/tag/" + i;
      y = l.getElementsByTagName(r)[0];
      y.parentNode.insertBefore(t, y);
    })(window, document, "clarity", "script", "jzg5x3cznq");
  }, []);

  useEffect(() => {
    if (window.clarity && shop?.shopify_domain) {
      window.clarity("identify", shop.shopify_domain);
      window.clarity("set", "shop", shop.shopify_domain);
    }
  }, [window.clarity, shop]);

  return null;
};

export default Clarity;
