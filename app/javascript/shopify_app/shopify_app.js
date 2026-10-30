/**
 * Built for Shopify 4.1.4: When on a sub-page, highlight the relevant parent nav item.
 * Note: ui-nav-menu rejects unexpected anchor attributes (e.g. aria-current),
 * so use CSS class toggling only.
 */
function highlightActiveNavItem() {
  const navMenu = document.querySelector("ui-nav-menu");
  if (!navMenu) return;

  const pathname = window.location.pathname;
  const links = navMenu.querySelectorAll("a[href]");

  // Paths that should highlight the Onboarding nav item (parent for quick-onboarding flows)
  const onboardingPaths = ["/onboarding", "/quick-onboarding"];

  links.forEach(function (link) {
    const href = link.getAttribute("href") || "";
    const isExactMatch = pathname === href;
    const isParentOfSubPage = href !== "/" && href.length > 1 && pathname.startsWith(href);
    const isOnboardingSection =
      (href === "/onboarding" || href === "/quick-onboarding") &&
      onboardingPaths.some(function (p) {
        return pathname === p || pathname.startsWith(p + "/");
      });

    link.classList.toggle(
      "codking-nav-active",
      isExactMatch || isParentOfSubPage || isOnboardingSection
    );
  });
}

document.addEventListener("DOMContentLoaded", function () {
  const data = document.getElementById("shopify-app-init").dataset;

  // Highlight the nav item for the current page (and parent for sub-pages)
  highlightActiveNavItem();

  // Re-run when URL changes (e.g. in-app pushState + popstate)
  window.addEventListener("popstate", highlightActiveNavItem);

  // Also run after a short delay so React navigation has updated the URL
  setTimeout(highlightActiveNavItem, 100);

  console.log("App Bridge Navigation initialized via Web Components.");
});