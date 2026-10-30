// import React, {useState, useContext, useEffect} from 'react';
// import { Card, Button, Link, Banner, List,Heading, FormLayout, Form, Layout,Page } from '@shopify/polaris';

// import I18n from '../i18n-lang'
// import { StoreContext } from "../Context/Store";

// const RecommendedCODFeeCheckout = () => {

//   const {
//     shop: [shop],
//   } = useContext(StoreContext);
//   return (
//     <>
//       <Banner status="info" title="Add fees in Checkout Page">
//         <List>
//           <List.Item>
//             <Link external url={`https://${shop.shopify_domain}/admin/settings/payments`}>
//               {'Go to Payment Settings'}
//             </Link>
//           </List.Item>
//           <List.Item>
//             Under Manual Payment methods - Select COD and add instructions.
//           </List.Item>
//           <List.Item>
//             Refer below sample recording.
//           </List.Item>
//         </List>
//       </Banner>
//       <Page fullWidth>
//       <Layout>
//         <Layout.Section>
//             <Heading> How to set it up </Heading>
//               <img src={'https://raw.githubusercontent.com/amandeep009/resources/7083b70d83c3dd1abe6c14b3bb740929fc89bfe7/CODFeePayment.gif'} alt='' style={{width: '100%', borderRadius: 3}} />
//             </Layout.Section>
//             <Layout.Section secondary>

//             <img src="https://github.com/amandeep009/resources/blob/main/CODCheckout.png?raw=true" alt='' style={{width: '100%', borderRadius: 3}} />
//             </Layout.Section>
//       </Layout>
//       </Page>
//     </>

//   )

// }

// export default RecommendedCODFeeCheckout
