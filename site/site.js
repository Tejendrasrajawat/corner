// Page behaviour: reveal-on-scroll, the nav's border once scrolled, the quick-add typing demo,
// the theme switcher and the live world clocks.
(() => {
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Reveal sections as they scroll in.
  const reveals = document.querySelectorAll(".reveal");
  if (reduceMotion || !("IntersectionObserver" in window)) {
    reveals.forEach((el) => el.classList.add("in"));
  } else {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        if (e.isIntersecting) {
          e.target.classList.add("in");
          io.unobserve(e.target);
        }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    reveals.forEach((el) => io.observe(el));
  }

  // Copy buttons next to commands.
  document.querySelectorAll("[data-copy]").forEach((button) => {
    button.addEventListener("click", () => {
      navigator.clipboard.writeText(document.getElementById(button.dataset.copy).textContent).then(() => {
        button.textContent = "Copied";
        setTimeout(() => { button.textContent = "Copy"; }, 1600);
      });
    });
  });

  // Nav gets a hairline once the page has scrolled.
  const nav = document.getElementById("nav");
  const onScroll = () => nav.classList.toggle("scrolled", window.scrollY > 8);
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  // Quick add: type an example, show what Corner would make of it, erase, repeat.
  const examples = [
    ["25m focus", "25 min timer · Focus"],
    ["fri 6pm release freeze", "Countdown to Fri, 18:00 · Release freeze"],
    ["every weekday 10am standup", "Every weekday at 10:00 · Standup"],
    ["buy milk", "To-do · buy milk"],
  ];
  const qaText = document.getElementById("qa-text");
  const qaPreview = document.getElementById("qa-preview");
  if (qaText && qaPreview) {
    if (reduceMotion) {
      qaText.textContent = examples[1][0];
      qaPreview.textContent = examples[1][1];
    } else {
      const wait = (ms) => new Promise((r) => setTimeout(r, ms));
      (async function loop() {
        for (let i = 0; ; i = (i + 1) % examples.length) {
          const [input, result] = examples[i];
          for (let n = 1; n <= input.length; n++) {
            qaText.textContent = input.slice(0, n);
            await wait(55 + Math.random() * 45);
          }
          qaPreview.textContent = result;
          qaPreview.style.opacity = "1";
          await wait(1900);
          qaPreview.style.opacity = "0";
          for (let n = input.length; n >= 0; n--) {
            qaText.textContent = input.slice(0, n);
            await wait(22);
          }
          await wait(350);
        }
      })();
    }
  }

  // Theme switcher: swap in the real app rendered in each theme.
  const glows = { aurora: "#8b5cf6", ocean: "#0ea5e9", sunset: "#f97316", forest: "#10b981", lavender: "#a855f7", midnight: "#312e81", system: "#64748b" };
  const shot = document.getElementById("themes-shot");
  const themeImg = document.getElementById("theme-img");
  const buttons = document.querySelectorAll(".swatches button");
  // Warm the cache so switching is instant.
  Object.keys(glows).forEach((t) => { const i = new Image(); i.src = `/img/site-theme-${t}.jpg`; });
  buttons.forEach((btn) => {
    btn.addEventListener("click", () => {
      const theme = btn.dataset.theme;
      buttons.forEach((b) => b.setAttribute("aria-pressed", String(b === btn)));
      themeImg.style.opacity = "0";
      setTimeout(() => {
        themeImg.src = `/img/site-theme-${theme}.jpg`;
        themeImg.alt = `Corner's card in the ${btn.textContent.trim()} theme`;
        themeImg.style.opacity = "1";
      }, 160);
      shot.style.setProperty("--glow", glows[theme]);
    });
  });

  // World clocks tile: the visitor's own time and UTC.
  const local = document.getElementById("clock-local");
  const localZone = document.getElementById("clock-local-zone");
  const utc = document.getElementById("clock-utc");
  if (local && utc) {
    const fmt = { hour: "numeric", minute: "2-digit" };
    try {
      localZone.textContent = Intl.DateTimeFormat().resolvedOptions().timeZone.split("/").pop().replace(/_/g, " ");
    } catch (_) { /* keep "Your time" */ }
    const tick = () => {
      const now = new Date();
      local.textContent = now.toLocaleTimeString([], fmt);
      utc.textContent = now.toLocaleTimeString([], { ...fmt, timeZone: "UTC" });
    };
    tick();
    setInterval(tick, 15000);
  }
})();
