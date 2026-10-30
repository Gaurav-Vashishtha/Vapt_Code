<script>
  /**
   * ScreenLayout - Main layout wrapper for all screens
   * Provides the device frame and content structure
   */
  import "../../styles/components/layouts/ScreenLayout.css";
  import "../../styles/components/layouts/ScreenLayout.mobile.css";
  import "../../styles/components/layouts/ScreenLayout.desktop.css";

  export let inBottomSheet = false; // When true, removes padding and frame styling
</script>

<div class="phone-screen" class:in-bottom-sheet={inBottomSheet}>
  <div class="device-frame" class:in-bottom-sheet={inBottomSheet}>
    <slot />
  </div>
</div>
