// import * as Sentry from '@sentry/react';
// import { Integrations } from '@sentry/tracing';

// if (process.env.NODE_ENV === 'garbage') {
//   Sentry.init({
//     dsn: process.env.SENTRY_REACT_DSN,
//     integrations: [new Integrations.BrowserTracing()],

//     // Set tracesSampleRate to 1.0 to capture 100%
//     // of transactions for performance monitoring.
//     // We recommend adjusting this value in production
//     tracesSampleRate: 0.0000001,
//     allowUrls: [
//       `${process.env.APP_HOST}`,
//       // `${host}/packs/js`
//     ]
//   });
// }

// export default Sentry;