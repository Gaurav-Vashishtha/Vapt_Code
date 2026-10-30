# Apollo Client Removal & Lightweight Client Implementation

# Table of Contents
- [1. Overview](#1-overview)
- [2. Code Walkthrough](#2-code-walkthrough)
- [3. API Call Analysis](#3-api-call-analysis)
- [4. Database Table Interaction](#4-database-table-interaction)
- [5. Implementing New GraphQL Calls (Developer Guide)](#5-implementing-new-graphql-calls-developer-guide)

---

## 1. Overview

This document details the removal of the `@apollo/client` library and its replacement with a custom, lightweight GraphQL client. The primary motivation for this change was to significantly reduce the application's JavaScript bundle size, leading to faster page load times and a better user experience.

### Bundle Size Optimization Results

The removal of Apollo Client resulted in a substantial reduction in the application's bundle size.

| Metric              | Before (with Apollo Client) | After (Lightweight Client) | Improvement                 |
| :------------------ | :-------------------------- | :------------------------- | :-------------------------- |
| **Resource Size**   | **~1,001 kB**               | **~787 kB** (projected)    | **~214 kB (~21% reduction)** |
| **Transferred Size**| **~261 kB**                 | **~190 kB** (projected)    | **~71 kB (~27% reduction)**  |

*Note: "Before" metrics are based on the production screenshot provided. "After" metrics are based on local build analysis and may vary slightly in the production environment.*

The new implementation achieves this while retaining all necessary functionality, including caching, request deduplication, and robust error handling.

<p align="right"><a href="#table-of-contents">⬆️ Back to Top</a></p>

---

## 2. Code Walkthrough

The changes were designed to be clear, maintainable, and easy for new developers to understand by replacing a complex library with explicit, dependency-free JavaScript.

### `app/javascript/packs/Modal/services/lightweightGraphQLClient.js` (New File)

*   **What it is:** A self-contained, lightweight client that handles all communication with the Shopify GraphQL API. It is the complete replacement for the Apollo Client library.
*   **Why it's better for maintenance:**
    *   **No Magic:** It's a plain JavaScript class using the standard browser `fetch` API. There are no complex internal mechanics or external dependencies.
    *   **Centralized:** All GraphQL communication logic is now in this one file, making it the single source of truth for how the application communicates with the server.

<details>
<summary>Click to see Before vs. After Code</summary>

#### Before
This file did not exist. GraphQL logic was handled by the `@apollo/client` library, configured in what was `apolloClient.js`.

#### After
```javascript
/**
 * Lightweight GraphQL Client - Apollo Client Replacement
 * Features: Error handling, caching, retry logic, and request deduplication
 */
class LightweightGraphQLClient {
  constructor(shopifyDomain, storefrontToken) {
    this.endpoint = `https://${shopifyDomain}/api/2024-07/graphql.json`;
    this.headers = {
      'X-Shopify-Storefront-Access-Token': storefrontToken,
      'Content-Type': 'application/json',
    };
    this.cache = new Map();
    // ... (rest of the client implementation)
  }

  async mutate(query, variables = {}, options = {}) {
    // ... handles caching, deduplication, and retries
  }

  async query(query, variables = {}, options = {}) {
    // ... alias for mutate
  }
  
  async mutateWithCacheClear(query, variables = {}, options = {}) {
    // ... mutation helper that always clears cache
  }
}

// Factory function to create client instance
export const createLightweightGraphQLClient = (shopifyDomain, storefrontToken) => {
  return new LightweightGraphQLClient(shopifyDomain, storefrontToken);
};
```
</details>

### `app/javascript/packs/Modal/services/errorHandler.js` (New File)

*   **What it is:** A centralized module for handling all GraphQL-related errors.
*   **Why it's better for maintenance:**
    *   **DRY (Don't Repeat Yourself):** Error handling logic is defined once.
    *   **Clean Business Logic:** Service files are no longer cluttered with `try...catch` blocks. The `executeWithErrorHandling` wrapper keeps the code clean.

<details>
<summary>Click to see Before vs. After Code</summary>

#### Before
This file did not exist. Error handling was done with inline `try...catch` blocks within each service function.

#### After
```javascript
/**
 * Error Handler for GraphQL Operations
 * Provides centralized error handling and user-friendly error messages
 */
export class GraphQLErrorHandler {
  // ...
  classifyError(error) {
    // ... logic to categorize errors (e.g., NETWORK_ERROR, AUTH_ERROR)
  }

  handleError(error, context = {}) {
    // ... returns a user-friendly message based on error type
  }

  async executeWithErrorHandling(operation, context = {}) {
    try {
      return await operation();
    } catch (error) {
      const errorResponse = this.handleError(error, context);
      // ... log and throw an enhanced error
      throw enhancedError;
    }
  }
}

export const errorHandler = new GraphQLErrorHandler();

export const executeWithErrorHandling = (operation, context = {}) => {
  return errorHandler.executeWithErrorHandling(operation, context);
};
```
</details>

### `app/javascript/packs/Modal/services/cartService.js` (Modified)

*   **What was changed:** Refactored to use the new `lightweightGraphQLClient` and `errorHandler`.
*   **Why it's better for maintenance:** The code is now more declarative and decoupled from a specific library.

<details>
<summary>Click to see Before vs. After Code</summary>

#### Before
```javascript
import { gql } from "@apollo/client";
import { getClient } from "../graphQl/apolloClient";

const CART_CREATE_MUTATION = gql`...`;

export const createCart = async (variables) => {
  try {
    const client = getClient();
    const { data } = await client.mutate({
      mutation: CART_CREATE_MUTATION,
      variables,
    });
    // ...
  } catch (error) {
    console.error("Error creating cart:", error);
    throw error;
  }
};
```

#### After
```javascript
import { createLightweightGraphQLClient } from "./lightweightGraphQLClient";
import { executeWithErrorHandling } from "./errorHandler";

const CART_CREATE_MUTATION = `...`; // Plain string, no gql tag

export const createCart = async (variables) => {
  return executeWithErrorHandling(async () => {
    // ... get shopifyDomain and storefrontToken
    const client = createLightweightGraphQLClient(shopifyDomain, storefrontToken);
    const { data } = await client.mutateWithCacheClear(CART_CREATE_MUTATION, variables);
    // ...
  });
};
```
</details>

### `app/javascript/packs/Modal/graphQl/apolloClient.js` (Modified)

*   **What was changed:** Repurposed to initialize our new lightweight client instead of the full Apollo Client.
*   **Why it's better for maintenance:** Maintained the existing `getClient` interface, which minimized the refactoring required in other parts of the codebase.

<details>
<summary>Click to see Before vs. After Code</summary>

#### Before
```javascript
import { ApolloClient, InMemoryCache, HttpLink } from "@apollo/client";
import { getSessionValue } from "../utilities/otpUtils";

let client = null;

const initializeClient = (storefrontAccessToken) => {
  const shopifyDomain = window.Shopify.shop;
  client = new ApolloClient({
    link: new HttpLink({
      uri: `https://${shopifyDomain}/api/2024-07/graphql.json`,
      headers: { "X-Shopify-Storefront-Access-Token": storefrontAccessToken },
    }),
    cache: new InMemoryCache(),
  });
};
// ... logic to wait for settings and initialize
```

#### After
```javascript
import { createLightweightGraphQLClient } from "../services/lightweightGraphQLClient";
import { getSessionValue } from "../utilities/otpUtils";

let client = null; // Instance is now our lightweight client

// Function signature remains the same
const initializeClient = (storefrontAccessToken) => {
  const shopifyDomain = window.Shopify.shop;
  // Initializes our new client instead of Apollo's
  client = createLightweightGraphQLClient(shopifyDomain, storefrontAccessToken);
};
// ... logic to wait for settings and initialize
```
</details>

### `app/javascript/packs/Modal/components/OTPManager.js` (Modified)

*   **What was changed:** The `<ApolloProvider>` component was removed from the React component tree.
*   **Why it's better for maintenance:** This decouples the UI from the data-fetching mechanism and simplifies the component hierarchy.

<details>
<summary>Click to see Before vs. After Code</summary>

#### Before
```javascript
import { ApolloProvider } from "@apollo/client";

const OTPManager = ({ showModal, handleCloseModal }) => {
  const [client, setClient] = useState(null);
  
  useEffect(() => {
    // ... logic to create Apollo Client instance
    setClient(newClient);
  }, []);

  if (!client) return <div>Loading...</div>;

  return (
    <ApolloProvider client={client}>
      <PageContainer>
        {/* ... child components ... */}
      </PageContainer>
    </ApolloProvider>
  );
};
```

#### After
```javascript
// Apollo Client imports removed

const OTPManager = ({ showModal, handleCloseModal }) => {
  const [clientReady, setClientReady] = useState(false);
  
  useEffect(() => {
    // ... lightweight client is initialized globally now
    setClientReady(true);
  }, []);

  if (!clientReady) return <div>Loading...</div>;

  // No ApolloProvider wrapper is needed
  return (
    <PageContainer>
      {/* ... child components ... */}
    </PageContainer>
  );
};
```
</details>

<p align="right"><a href="#table-of-contents">⬆️ Back to Top</a></p>

---

## 3. API Call Analysis

This section details each GraphQL API call made by the application.

### A. Create Cart

*   **File:** `cartService.js`
*   **Function:** `createCart`
*   **Trigger:** This function is called when the user initiates an action that requires a new Shopify cart to be created, such as clicking a "Buy Now" or "Pre-Order" button. This is typically triggered from the `ButtonManager.js` component when either the `isPreOrderOtpEnabled` or `partialPaymentEnabled` settings are active.

**Sample Request:**
```json
{
  "query": "mutation CartCreate($lines: [CartLineInput!]!) { cartCreate(input: { lines: $lines }) { cart { id checkoutUrl } } }",
  "variables": {
    "lines": [
      {
        "quantity": 1,
        "merchandiseId": "gid://shopify/ProductVariant/40000000000001"
      }
    ]
  }
}
```

**Sample Response (Success):**
```json
{
  "data": {
    "cartCreate": {
      "cart": {
        "id": "gid://shopify/Cart/c1-1234567890abcdef",
        "checkoutUrl": "https://your-shop.myshopify.com/cart/c/c1-1234567890abcdef"
      }
    }
  }
}
```

<p align="right"><a href="#table-of-contents">⬆️ Back to Top</a></p>

### B. Update Cart Buyer Identity

*   **File:** `cartService.js`
*   **Function:** `updateBuyerIdentity`
*   **Trigger:** Called immediately after a cart is successfully created. Its purpose is to attach the customer's identity (like email or phone number, if available) to the cart for a smoother checkout process.

**Sample Request:**
```json
{
  "query": "mutation cartBuyerIdentityUpdate($cartId: ID!, $buyerIdentity: CartBuyerIdentityInput!) { cartBuyerIdentityUpdate(cartId: $cartId, buyerIdentity: $buyerIdentity) { cart { id buyerIdentity { email phone } } userErrors { field message } } }",
  "variables": {
    "cartId": "gid://shopify/Cart/c1-1234567890abcdef",
    "buyerIdentity": {
      "email": "customer@example.com"
    }
  }
}
```

**Sample Response (Success):**
```json
{
  "data": {
    "cartBuyerIdentityUpdate": {
      "cart": {
        "id": "gid://shopify/Cart/c1-1234567890abcdef",
        "buyerIdentity": {
          "email": "customer@example.com",
          "phone": null
        }
      },
      "userErrors": []
    }
  }
}
```

<p align="right"><a href="#table-of-contents">⬆️ Back to Top</a></p>

### C. Apply Discount Code

*   **File:** `cartService.js`
*   **Function:** `applyDiscountCodeToCart`
*   **Trigger:** This function is called when a user submits a discount code in the UI.

**Sample Request:**
```json
{
  "query": "mutation cartDiscountCodesUpdate($cartId: ID!, $discountCodes: [String!]) { cartDiscountCodesUpdate(cartId: $cartId, discountCodes: $discountCodes) { cart { id discountCodes { code applicable } } userErrors { field message } } }",
  "variables": {
    "cartId": "gid://shopify/Cart/c1-1234567890abcdef",
    "discountCodes": ["SUMMERSALE"]
  }
}
```

**Sample Response (Success):**
```json
{
  "data": {
    "cartDiscountCodesUpdate": {
      "cart": {
        "id": "gid://shopify/Cart/c1-1234567890abcdef",
        "discountCodes": [
          {
            "code": "SUMMERSALE",
            "applicable": true
          }
        ]
      },
      "userErrors": []
    }
  }
}
```

<p align="right"><a href="#table-of-contents">⬆️ Back to Top</a></p>

### D. Create Shopify Customer

*   **File:** `customerCredentialService.js`
*   **Function:** `createShopifyCustomer`
*   **Trigger:** Called when the application needs to create a new customer account in Shopify. This typically happens as part of the OTP verification flow or an initial user sign-up process before checkout.

**Sample Request:**
```json
{
  "query": "mutation customerCreate($input: CustomerCreateInput!) { customerCreate(input: $input) { customer { id email phone } userErrors { field message } } }",
  "variables": {
    "input": {
      "email": "new.customer@example.com",
      "password": "SecurePassword123"
    }
  }
}
```

**Sample Response (Success):**
```json
{
  "data": {
    "customerCreate": {
      "customer": {
        "id": "gid://shopify/Customer/1234567890",
        "email": "new.customer@example.com",
        "phone": null
      },
      "userErrors": []
    }
  }
}
```

<p align="right"><a href="#table-of-contents">⬆️ Back to Top</a></p>

---

## 4. Database Table Interaction

The GraphQL calls are made to the Shopify Storefront API, meaning they primarily read from and write to **Shopify's internal database**. However, this application's local PostgreSQL database stores related information for its own business logic (e.g., logging, scheduling, analytics).

Below is a summary of how the GraphQL calls relate to the local database tables defined in `db/schema.rb`.

### `customerCreate`

*   **Primary Action**: Creates a new customer record in Shopify's database.
*   **Related Local Tables**: When a customer is created via the API, the application's logic will likely create corresponding records in the following tables to mirror the Shopify data and add its own metadata:
    *   `customers`: The central table for storing core customer information (phone, email, name).
    *   `customer_logins`: Stores customer credential information.
    *   `customer_addresses`: Stores one or more addresses linked to a record in the `customers` table.
    *   `customer_shop_mappings`: A join table that links a customer to the specific `shops` record they belong to, and tracks their lifetime value.

### `cartCreate`, `cartBuyerIdentityUpdate`, `cartDiscountCodesUpdate`

*   **Primary Action**: These mutations create and modify a temporary `Cart` object within Shopify's database. Carts are generally ephemeral and do not have a permanent record until they are converted into an `Order`.
*   **Related Local Tables**: The application has a sophisticated system for tracking the journey of a cart, especially for abandoned cart recovery and order confirmation flows.
    *   `abandon_cart_schedules` / `abandoned_carts`: These are the most relevant tables. After a cart is created in Shopify, its ID (`checkout_id` or `cart_id`) is stored in these tables to schedule follow-up notifications (SMS/WhatsApp) if the user does not complete the purchase.
    *   `pre_order_otps`: For pre-order flows, this table tracks the OTP verification process. It stores the `cart_details` in a JSON field, creating a direct link between a verification attempt and the contents of a specific cart.
    *   `order_confirmations`: Once a cart is successfully converted into an order, a record is created here to log the confirmation status, OTP details, and any post-purchase events.

<p align="right"><a href="#table-of-contents">⬆️ Back to Top</a></p>

---

## 5. Implementing New GraphQL Calls (Developer Guide)

Adding new GraphQL calls with the new system is straightforward. The process is designed to be simple and consistent. Here is a step-by-step guide with examples.

### Step 1: Define Your GraphQL Query or Mutation

Write your query or mutation as a plain JavaScript template string. You no longer need the `gql` tag from Apollo Client.

**Example Query:**
```javascript
const GET_PRODUCT_BY_ID = `
  query GetProductById($id: ID!) {
    product(id: $id) {
      id
      title
      description
      priceRange {
        minVariantPrice {
          amount
          currencyCode
        }
      }
    }
  }
`;
```

### Step 2: Create a Service Function

In the appropriate service file (e.g., `productService.js` or `customerService.js`), create a new `async` function. This function should be wrapped with `executeWithErrorHandling` to ensure all errors are processed by the central handler.

### Step 3: Implement the Function Logic

Inside your new function, get the required Shopify domain and storefront token, create an instance of the `LightweightGraphQLClient`, and call the appropriate method (`.query()` for queries, `.mutate()` or `.mutateWithCacheClear()` for mutations).

---

### Example 1: Implementing a New Query

Let's say you need to fetch a product by its ID.

```javascript
// In a file like `/services/productService.js`

import { createLightweightGraphQLClient } from "./lightweightGraphQLClient";
import { executeWithErrorHandling } from "./errorHandler";
import { getSessionValue } from "../utilities/otpUtils";

// 1. Define the Query
const GET_PRODUCT_BY_ID = `
  query GetProductById($id: ID!) {
    product(id: $id) {
      id
      title
      description
    }
  }
`;

// 2. Create the service function
export const getProductById = async (productId) => {
  // 3. Wrap with error handler
  return executeWithErrorHandling(async () => {
    // 4. Get config and create client
    const settings = getSessionValue("settingSession");
    const shopifyDomain = window.Shopify?.shop;
    const storefrontToken = settings?.storeFrontToken;

    if (!shopifyDomain || !storefrontToken) {
      throw new Error("Shopify configuration not found");
    }

    const client = createLightweightGraphQLClient(shopifyDomain, storefrontToken);

    // 5. Execute the query
    const result = await client.query(GET_PRODUCT_BY_ID, { id: productId });

    // The client returns the `data` object from the GraphQL response
    return result.data.product;
  }, { operation: 'getProductById' }); // Context is useful for debugging
};
```

### Example 2: Implementing a New Mutation

Let's say you need to update a customer's note (this is a hypothetical mutation).

```javascript
// In a file like `/services/customerService.js`

import { createLightweightGraphQLClient } from "./lightweightGraphQLClient";
import { executeWithErrorHandling } from "./errorHandler";
import { getSessionValue } from "../utilities/otpUtils";

// 1. Define the Mutation
const UPDATE_CUSTOMER_NOTE = `
  mutation UpdateCustomerNote($customerId: ID!, $note: String!) {
    customerUpdate(input: { id: $customerId, note: $note }) {
      customer {
        id
        note
      }
      userErrors {
        field
        message
      }
    }
  }
`;

// 2. Create the service function
export const updateCustomerNote = async (customerId, note) => {
  // 3. Wrap with error handler
  return executeWithErrorHandling(async () => {
    // 4. Get config and create client
    const settings = getSessionValue("settingSession");
    const shopifyDomain = window.Shopify?.shop;
    const storefrontToken = settings?.storeFrontToken;

    if (!shopifyDomain || !storefrontToken) {
      throw new Error("Shopify configuration not found");
    }

    const client = createLightweightGraphQLClient(shopifyDomain, storefrontToken);

    // 5. Execute the mutation
    // Use `mutateWithCacheClear` if the action should invalidate cached data.
    const result = await client.mutateWithCacheClear(UPDATE_CUSTOMER_NOTE, { 
      customerId: customerId,
      note: note 
    });

    if (result.data?.customerUpdate?.userErrors?.length > 0) {
      throw new Error(result.data.customerUpdate.userErrors[0].message);
    }

    return result.data.customerUpdate.customer;
  }, { operation: 'updateCustomerNote' });
};
```

<p align="right"><a href="#table-of-contents">⬆️ Back to Top</a></p>
