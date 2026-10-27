// The page's own copy of Corner: a 25-minute Focus timer that starts when you arrive, the visitor's
// local clock, and a countdown to the weekend. Hover grows it, click opens the card, like the app.
(() => {
  const RING = 147.65; // length of the quarter arc in the SVG
  const started = Date.now();
  const focus = 25 * 60;
  const $ = (id) => document.getElementById(id);
  const face = $("demo-face");
  const card = $("demo-card");

  const pad = (n) => String(n).padStart(2, "0");
  const mmss = (s) => `${pad(Math.floor(s / 60))}:${pad(s % 60)}`;

  function weekendIn(now) {
    const target = new Date(now);
    target.setHours(0, 0, 0, 0);
    target.setDate(target.getDate() + ((6 - target.getDay() + 7) % 7 || 7));
    const s = Math.max(0, Math.floor((target - now) / 1000));
    const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
    return d > 0 ? `${d}d ${pad(h)}h ${pad(m)}m` : `${h}h ${pad(m)}m`;
  }

  function tick() {
    const now = new Date();
    const elapsed = Math.floor((Date.now() - started) / 1000);
    const left = Math.max(0, focus - elapsed);
    const progress = Math.min(1, elapsed / focus);
    $("demo-value").textContent = mmss(left);
    $("demo-timer").textContent = mmss(left);
    $("demo-ring").style.strokeDashoffset = String(RING * (1 - Math.max(progress, 0.02)));
    $("demo-bar").style.width = `${(progress * 100).toFixed(1)}%`;
    $("demo-clock").textContent = now.toLocaleTimeString([], { hour: "numeric", minute: "2-digit", second: "2-digit" });
    $("demo-weekend").textContent = weekendIn(now);
  }

  function setOpen(open) {
    card.hidden = !open;
    face.hidden = open;
    face.setAttribute("aria-expanded", String(open));
    if (open) $("demo-close").focus();
    else face.focus();
  }

  try {
    $("demo-zone").textContent = Intl.DateTimeFormat().resolvedOptions().timeZone.replace(/_/g, " ");
  } catch (_) { /* keep "Your time" */ }

  face.addEventListener("click", () => setOpen(true));
  $("demo-close").addEventListener("click", () => setOpen(false));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape" && !card.hidden) setOpen(false); });
  document.addEventListener("click", (e) => {
    if (!card.hidden && !card.contains(e.target) && e.target !== face && !face.contains(e.target)) setOpen(false);
  });

  tick();
  setInterval(tick, 1000);
})();
