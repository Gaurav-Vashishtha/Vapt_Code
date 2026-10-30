<script>
  import "../../styles/components/shared/VerifiedAnimation.css";
  export let width = 220;
  export let height = 220;
  const source =
    "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/Cart.gif?v=1763464317";
</script>

<div
  class="verified-animation"
  role="img"
  aria-label="Payment verified animation"
>
  <img
    src={source}
    alt="Processing animation"
    {width}
    {height}
    loading="lazy"
  />
</div>
