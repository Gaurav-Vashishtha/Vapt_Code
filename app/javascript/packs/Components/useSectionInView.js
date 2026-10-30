import { useCallback, useEffect, useRef, useState } from "react";

/**
 * Which settings card is the merchant reading?
 *
 * A screen with two previews used to stack both in the right rail, so the one
 * that mattered was often off screen while the other took up the space. This
 * lets a single sticky panel show the preview belonging to whichever card has
 * reached the top of the viewport, and swap as the merchant scrolls.
 *
 * Usage:
 *   const { active, register } = useSectionInView(["banner", "message"]);
 *   <div ref={register("banner")}>…</div>
 *   {active === "message" ? <MessagePreview /> : <BannerPreview />}
 *
 * `keys` must be a stable array (module constant or memoised), in the order the
 * sections appear down the page.
 */
const READING_LINE = 160; // px from the top; roughly where the eye sits

/**
 * The section sitting on the reading line.
 *
 * Pure so it can be tested without a browser: `sections` is
 * [{ key, top, bottom }] in page order, top/bottom being viewport offsets.
 *
 * `atBottom` matters more than it looks. The last section on a page can never
 * climb to the reading line, because there is nothing below it left to scroll
 * past; without this the final preview would simply never appear.
 */
export const pickActiveSection = (
  sections,
  { offset = READING_LINE, atBottom = false } = {},
) => {
  const known = sections.filter((section) => section.top != null);
  if (!known.length) return sections.length ? sections[0].key : undefined;

  if (atBottom) return known[known.length - 1].key;

  const onTheLine = known.find(
    (section) =>
      section.top <= offset && (section.bottom == null || section.bottom > offset),
  );
  if (onTheLine) return onTheLine.key;

  // Gaps between sections: fall back to the last one already scrolled past.
  let current = known[0].key;
  let closest = -Infinity;
  known.forEach(({ key, top }) => {
    const distance = top - offset;
    if (distance <= 0 && distance > closest) {
      closest = distance;
      current = key;
    }
  });
  return current;
};

export const useSectionInView = (keys, { offset = READING_LINE } = {}) => {
  const nodes = useRef({});
  const [active, setActive] = useState(keys[0]);

  const register = useCallback(
    (key) => (node) => {
      if (node) nodes.current[key] = node;
      else delete nodes.current[key];
    },
    [],
  );

  useEffect(() => {
    // A scroll listener rather than IntersectionObserver: the question is not
    // "is this visible" but "which one did I last scroll past", and tall cards
    // can cover the whole viewport, where every observer entry reads the same.
    let frame = null;

    const measure = () => {
      frame = null;
      const measured = keys.map((key) => {
        const node = nodes.current[key];
        if (!node) return { key, top: null, bottom: null };
        const rect = node.getBoundingClientRect();
        return { key, top: rect.top, bottom: rect.bottom };
      });

      const doc = document.documentElement;
      const scrollable = doc.scrollHeight - window.innerHeight > offset;
      const atBottom =
        scrollable &&
        window.innerHeight + window.scrollY >= doc.scrollHeight - 2;

      const current = pickActiveSection(measured, { offset, atBottom });
      setActive((prev) => (prev === current ? prev : current));
    };

    const onScroll = () => {
      if (frame !== null) return;
      frame = window.requestAnimationFrame(measure);
    };

    measure();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    return () => {
      if (frame !== null) window.cancelAnimationFrame(frame);
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
    };
  }, [keys, offset]);

  return { active, register };
};

export default useSectionInView;
