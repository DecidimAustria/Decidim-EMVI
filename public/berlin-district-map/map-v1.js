/* Native SVG links work without JavaScript. Only the hover label is enhanced. */
(() => {
  const initialize = () => {
    const root = document.querySelector("#berlin-district-map");
    const svg = root?.querySelector("#berlinCard");
    if (!svg || svg.dataset.initialized) return;
    svg.dataset.initialized = "true";
    svg.querySelectorAll(".districts a").forEach((link) => {
      const path = link.querySelector("path[id]");
      const label = path && svg.querySelector(`#${CSS.escape(path.id)}Text`);
      if (!label) return;
      link.addEventListener("mouseenter", () => { label.style.visibility = "hidden"; });
      link.addEventListener("mouseleave", () => { label.style.visibility = ""; });
    });
  };
  if (document.readyState !== "loading") initialize();
  document.addEventListener("DOMContentLoaded", initialize);
  document.addEventListener("turbo:load", initialize);
})();
