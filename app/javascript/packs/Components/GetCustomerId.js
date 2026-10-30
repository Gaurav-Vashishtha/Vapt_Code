 const getCustomerId = () => {
  try {
    let curr = window.ShopifyAnalytics.meta.page.customerId;
    if (curr !== undefined && curr !== null && curr !== '') {
      return curr;
    }
  } catch(e) { }
  try {
    let curr = window.meta.page.customerId;
    if (curr !== undefined && curr !== null && curr !== '') {
      return curr;
    }
  } catch (e) { }    
  try {
    let curr = __st.cid;
    if (curr !== undefined && curr !== null && curr !== '') {
      return curr;
    }
  } catch (e) { }
  // try {
  //   // returns uuid kind of token even when not logged in
  //   let curr = ShopifyAnalytics.lib.user().traits().uniqToken;
  //   if (curr !== undefined && curr !== null && curr !== '') {
  //     return curr;
  //   }
  // } catch (e) { }
  return null;
};

export default getCustomerId;