<script>
  import LegalFooter from "../shared/LegalFooter.svelte";
  /**
   * Footer - Terms, Privacy, and Security footer
   * @component
   */
  export let termsUrl =
    "https://codking.notion.site/Terms-and-Conditions-COD-King-1a96e71a63f980358f6fe23c3c96485c";
  export let privacyUrl =
    "https://codking.notion.site/Privacy-Policy-COD-King-1ab6e71a63f980fb882df2e6a7173576";
  export let logoUrl =
    "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/CKlogoicon-1200px_1.png?v=1762758841";
</script>

<LegalFooter {termsUrl} {privacyUrl} {logoUrl} />
