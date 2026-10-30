# Testing Guide: Phase 0 Foundation

## 🚀 Quick Start Testing

### Option 1: Development Mode (Hot Reload)

1. **Start the Vite dev server:**

```bash
cd cod-confirm/notifik-svelte-app
npm run dev
```

This will:

- Start Vite dev server on `http://localhost:5173`
- Enable hot module replacement (auto-reload on changes)
- Show build errors in terminal

2. **Open browser console:**

- Open your Shopify store page
- Press `F12` or `Cmd+Option+I` (Mac) / `Ctrl+Shift+I` (Windows)
- Go to **Console** tab

3. **Check for initialization:**
   Look for these console messages:

```
[notifik-svelte.js] 🚀 Svelte app starting...
[notifik-svelte.js] ✅ Svelte ready - window.parent.codkingSvelteReady = true
[notifik-svelte.js] 📢 Dispatched 'codking-svelte-ready' event
```

### Option 2: Production Build Testing

1. **Build the app:**

```bash
cd cod-confirm/notifik-svelte-app
npm run build:dev  # Development build (with source maps)
# OR
npm run build:prod # Production build (minified)
```

2. **Check build output:**

```bash
ls -la ../public/notifik-svelte-app/
```

You should see:

- `notifik-svelte.[hash].js` - Main bundle
- `manifest.json` - Build manifest
- `chunks/` - Code splitting chunks (if any)
- `assets/` - CSS and other assets

3. **Test in browser:**

- Open your Shopify store
- Open browser console
- Check for errors

---

## 🔍 Browser Console Checks

### 1. Check if Services Load

Open browser console and run:

```javascript
// Check if API service is available
import("/notifik-svelte-app/notifik-svelte.[hash].js")
  .then((module) => {
    console.log("✅ Svelte app loaded");
  })
  .catch((err) => {
    console.error("❌ Failed to load:", err);
  });
```

### 2. Test API Service

In browser console (after app loads):

```javascript
// Access the app store (exposed via window.appStore)
if (window.appStore) {
  console.log("✅ App store available");
  window.appStore.subscribe((state) => {
    console.log("Store state:", state);
  });
} else {
  console.error("❌ App store not found");
}
```

### 3. Test Session Service

```javascript
// Test session storage
const { getSessionValue, setSessionValue } = await import(
  "/notifik-svelte-app/notifik-svelte.[hash].js"
);
// Note: This won't work directly - services are not exported globally
// Instead, check via app store
```

### 4. Check for Errors

Look for these in console:

- ❌ Red errors: Fix immediately
- ⚠️ Yellow warnings: Review but may be non-critical
- ✅ Green/blue logs: Normal operation

---

## 🧪 Manual Testing Checklist

### Phase 0 Services Testing

#### ✅ API Service (`src/services/api.js`)

**Test 1: Route URL Detection**

```javascript
// In browser console, check if routeUrl is available
console.log("Route URL:", window.parent?.codkingRouteUrl || "Not found");
```

**Test 2: Settings Loading**

```javascript
// Check if settings are in sessionStorage
const settings = JSON.parse(sessionStorage.getItem("settingSession") || "{}");
console.log("Settings:", settings);
console.log("Route URL in settings:", settings.routeUrl);
```

#### ✅ Helper Functions (`src/utils/helpers.js`)

**Test in browser console:**

```javascript
// These won't work directly, but you can test via the app
// Check if machine ID is generated
console.log("Machine ID:", sessionStorage.getItem("MachineId"));

// Test currency formatting (if exposed)
// Should see formatted currency in UI
```

#### ✅ Cart Service (`src/services/cartService.js`)

**Test cart fetching:**

```javascript
// In browser console
fetch("/cart.js")
  .then((r) => r.json())
  .then((cart) => {
    console.log("✅ Cart fetched:", cart);
    console.log("Items:", cart.items?.length);
    console.log("Total:", cart.total_price);
  })
  .catch((err) => console.error("❌ Cart fetch failed:", err));
```

#### ✅ Session Service (`src/services/sessionService.js`)

**Test session storage:**

```javascript
// Check if session storage is working
sessionStorage.setItem("test", "value");
console.log("✅ Session storage works:", sessionStorage.getItem("test"));

// Check OTP verification flag
const verified = JSON.parse(
  sessionStorage.getItem("verifiedNumberData") || "{}"
);
console.log("OTP Verified:", verified.isOTPVerified || false);
```

#### ✅ Store (`src/stores/appStore.js`)

**Test store state:**

```javascript
// Check if store is exposed (via App.svelte)
if (window.appStore) {
  window.appStore.subscribe((state) => {
    console.log("Current screen:", state.currentScreen);
    console.log("Settings loaded:", !!state.settings);
    console.log("Phone number:", state.phoneNumber);
  });
} else {
  console.error("❌ Store not exposed - check App.svelte");
}
```

---

## 🐛 Debugging Tips

### 1. Enable Debug Mode

The services have `DEBUG_MODE = true` by default. You should see:

- `[API Service]` logs
- `[Cart Service]` logs
- `[Session Service]` logs
- `[Helpers]` logs

### 2. Check Network Tab

1. Open **Network** tab in DevTools
2. Filter by `JS` or `Fetch/XHR`
3. Look for:
   - `notifik-svelte.[hash].js` - Should load successfully (200)
   - API calls to `/order_confirmations/*` - Check if they're made
   - Settings fetch - Should return JSON

### 3. Check Sources Tab

1. Open **Sources** tab in DevTools
2. Navigate to your files:
   - `notifik-svelte-app/src/services/api.js`
   - `notifik-svelte-app/src/utils/helpers.js`
   - etc.
3. Set breakpoints to debug

### 4. Common Issues

**Issue: "ROUTE_URL not found"**

- **Fix:** Ensure `notifik_svelte.liquid` sets `window.codkingRouteUrl`
- **Check:** `window.parent.codkingRouteUrl` in console

**Issue: "Shopify.shop not found"**

- **Fix:** Ensure you're testing on a Shopify store page
- **Check:** `window.Shopify?.shop` in console

**Issue: "Module not found"**

- **Fix:** Rebuild the app: `npm run build:dev`
- **Check:** Verify `manifest.json` exists in `public/notifik-svelte-app/`

**Issue: "Store not exposed"**

- **Fix:** Check `App.svelte` - should have `window.appStore = appStore`
- **Check:** Verify app is mounted correctly

---

## 📝 Quick Test Script

Create a test HTML file to verify services work:

```html
<!DOCTYPE html>
<html>
  <head>
    <title>Phase 0 Services Test</title>
  </head>
  <body>
    <h1>Phase 0 Services Test</h1>
    <div id="test-results"></div>

    <script type="module">
      const results = document.getElementById("test-results");

      // Test 1: Check if services can be imported
      async function testServices() {
        try {
          // Note: Adjust path based on your setup
          const apiModule = await import("./src/services/api.js");
          console.log("✅ API service imported:", Object.keys(apiModule));

          const helpersModule = await import("./src/utils/helpers.js");
          console.log("✅ Helpers imported:", Object.keys(helpersModule));

          const cartModule = await import("./src/services/cartService.js");
          console.log("✅ Cart service imported:", Object.keys(cartModule));

          const sessionModule = await import(
            "./src/services/sessionService.js"
          );
          console.log(
            "✅ Session service imported:",
            Object.keys(sessionModule)
          );

          results.innerHTML =
            '<p style="color: green;">✅ All services loaded successfully!</p>';
        } catch (error) {
          console.error("❌ Service import failed:", error);
          results.innerHTML = `<p style="color: red;">❌ Error: ${error.message}</p>`;
        }
      }

      testServices();
    </script>
  </body>
</html>
```

---

## 🎯 Integration Testing

### Test with Shopify Store

1. **Ensure Svelte app is active:**

   - Check `app-embed.liquid`: `IS_SVELTE_APP_ACTIVE = true`

2. **Load a product page:**

   - Add item to cart
   - Click checkout/buy now button

3. **Expected behavior:**

   - Modal should open (if implemented)
   - Console should show initialization logs
   - No JavaScript errors

4. **Check console for:**
   ```
   [notifik-svelte.js] 🚀 Svelte app starting...
   [notifik-svelte.js] 🔧 Fetching settings from: [URL]
   [notifik-svelte.js] ✅ Raw settings loaded: [object]
   [notifik-svelte.js] ✅ Svelte ready
   ```

---

## 🔧 Development Workflow

### Recommended Workflow:

1. **Terminal 1: Vite Dev Server**

   ```bash
   cd notifik-svelte-app
   npm run dev
   ```

2. **Terminal 2: Rails Server** (if testing integration)

   ```bash
   cd cod-confirm
   rails s
   ```

3. **Browser:**

   - Open DevTools (F12)
   - Go to Console tab
   - Watch for logs and errors

4. **Make changes:**
   - Edit files in `src/`
   - Vite will auto-reload
   - Check console for new logs

---

## ✅ Success Indicators

You'll know Phase 0 is working when:

1. ✅ **No console errors** on page load
2. ✅ **Settings loaded** (check `sessionStorage.settingSession`)
3. ✅ **Machine ID generated** (check `sessionStorage.MachineId`)
4. ✅ **Store initialized** (check `window.appStore`)
5. ✅ **Services can be imported** (no module errors)
6. ✅ **Cart can be fetched** (test `/cart.js` endpoint)

---

## 🚨 Troubleshooting

### Build Errors

```bash
# Clear node_modules and reinstall
rm -rf node_modules package-lock.json
npm install

# Rebuild
npm run build:dev
```

### Import Errors

- Check file paths are correct
- Ensure exports are named correctly
- Verify `package.json` has correct `type: "module"`

### Runtime Errors

- Check browser console for specific error messages
- Verify all dependencies are installed
- Check if running in correct environment (browser vs Node)

---

## 📊 Next Steps

Once Phase 0 is verified:

1. ✅ All services load without errors
2. ✅ Store initializes correctly
3. ✅ Session storage works
4. ✅ API endpoints are accessible

**Then proceed to Phase 1:** Phone Input Screen implementation
