import axios from 'axios';
import { camelizeKeys, decamelizeKeys } from 'humps';
import { getSessionToken } from '@shopify/app-bridge-utils';
import { getIdToken } from '../utils/idToken';

const instance = axios.create();
// intercept all requests on this axios instance
instance.interceptors.request.use(
  async function (config) {
    try {
      // Use the new v4 method to get the token
      // Bounded so a hung App Bridge can't stall every request forever.
      const token = await getIdToken();
      
      config.headers['Authorization'] = `Bearer ${token}`;
      // Rails CSRF: include token so verify_authenticity_token passes for POST/PATCH/DELETE
      const csrfMeta = document.querySelector('meta[name="csrf-token"]');
      if (csrfMeta) {
        config.headers['X-CSRF-Token'] = csrfMeta.getAttribute('content');
      }
      return config;
    } catch (error) {
      console.error("Failed to retrieve Shopify ID token", error);
      return config;
    }
  }
);

instance.interceptors.request.use(request => {
  request.data = decamelizeKeys(request.data)
  return request;
});

instance.interceptors.response.use(response => {
  response.data = camelizeKeys(response.data)
  return response;
});

// instance.interceptors.response.use(
//   response => {
//     response.data = camelizeKeys(response.data);
//     return response;
//   },
//   error => {
//     if (error.response?.status === 429) {
//       if (!window.__codKing429ReloadScheduled) {
//         window.__codKing429ReloadScheduled = true;
//         const delayMs = 3000;
//         console.warn(`[COD King] Too many requests (429). Reloading in ${delayMs / 1000}s.`);
//         setTimeout(() => window.location.reload(), delayMs);
//       }
//     }
//     return Promise.reject(error);
//   }
// );

// export your axios instance to use within your app
export default instance;