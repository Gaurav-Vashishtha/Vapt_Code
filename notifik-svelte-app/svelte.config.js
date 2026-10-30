import { vitePreprocess } from "@sveltejs/vite-plugin-svelte";

/** @type {import("@sveltejs/vite-plugin-svelte").SvelteConfig} */
export default {
  // Consult https://svelte.dev/docs#compile-time-svelte-preprocess
  // for more information about preprocessors
  preprocess: [
    vitePreprocess(),
    {
      markup: ({ content }) => {
        // Automatically convert modern event syntax (onclick, onChange, etc.)
        // to legacy Svelte syntax (on:click, on:change, etc.)
        // to avoid mixed syntax errors when the source code has both.
        // Svelte 5 allows legacy syntax as long as it's not mixed on the same element.
        // Using [a-zA-Z] to catch camelCase handlers like onChange.
        const code = content.replace(/\b(on[a-zA-Z]+)=/g, (match, modern) => {
          if (modern.startsWith("on:")) return match;
          const event = modern.slice(2).toLowerCase();
          return `on:${event}=`;
        });
        return { code };
      },
    },
  ],
};
