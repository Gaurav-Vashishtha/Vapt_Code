import { makeUseAxios } from 'axios-hooks'
import LRU from 'lru-cache'
import Axios from 'axios'
import { camelizeKeys, decamelizeKeys } from 'humps'
import { getSessionToken } from '@shopify/app-bridge-utils'

const axios = Axios.create({
  baseURL: `https://${process.env.APP_HOST}`
})

// intercept all requests on this axios instance
axios.interceptors.request.use(
  async function (config) {
    try {
      // In App Bridge v4, shopify.idToken() handles the token retrieval
      const token = await shopify.idToken();
      
      // Set the Authorization header
      config.headers['Authorization'] = `Bearer ${token}`;
      
      return config;
    } catch (error) {
      // Handle cases where the token cannot be retrieved (e.g., app is outside of Shopify admin)
      console.error("Shopify ID Token error:", error);
      return config;
    }
  },
  function (error) {
    return Promise.reject(error);
  }
);

axios.interceptors.request.use(request => {
  request.data = decamelizeKeys(request.data)
  return request;
});

axios.interceptors.response.use(response => {
  response.data = camelizeKeys(response.data)
  return response;
});
const cache = new LRU({ max: 10 })


const useAxios = makeUseAxios({
  axios, cache
})

export default useAxios;
