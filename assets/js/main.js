/* Nicoman Elevators — site behaviour
   1. Site details (edit SITE only; every phone, WhatsApp and email link reads from here)
   2. Mobile menu
   3. Scroll-driven elevator in the hoistway background
   4. Reveal-on-scroll
   5. Enquiry forms (spam checks, WhatsApp fallback, optional email endpoint)
*/
(() => {
  "use strict";

  /* 1. SITE DETAILS — replace the placeholders before launch */
  const SITE = {
    phoneDisplay: "+91 XXXXX XXXXX",
    phoneTel: "+91XXXXXXXXXX",
    whatsappNumber: "91XXXXXXXXXX", // digits only, with country code
    email: "your-email@example.com",
    address: "[Street address], Port Blair, Andaman and Nicobar Islands",
    hours: "Mon to Sat, [9:00 to 18:00]",
    // Set to the API Gateway URL once the backend in /backend is deployed. Empty = WhatsApp fallback only.
    formEndpoint: "",
  };

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  document.documentElement.classList.add("js");

  /* Fill every [data-site] text and every tel / WhatsApp / mail link from SITE */
  const waText = encodeURIComponent("Hello Nicoman Elevators, I'd like to enquire about your services.");
  $$("[data-site]").forEach((el) => {
    const v = SITE[el.dataset.site];
    if (v) el.textContent = v;
  });
  $$("[data-tel]").forEach((el) => (el.href = `tel:${SITE.phoneTel}`));
  $$("[data-wa]").forEach((el) => (el.href = `https://wa.me/${SITE.whatsappNumber}?text=${waText}`));
  $$("[data-mail]").forEach((el) => {
    el.href = `mailto:${SITE.email}`;
    if (!el.dataset.keepText) el.textContent = SITE.email;
  });
  $$("[data-year]").forEach((el) => (el.textContent = new Date().getFullYear()));

  /* 2. Mobile menu */
  const toggle = $(".nav__toggle");
  const header = $(".site-header");
  if (toggle && header) {
    toggle.addEventListener("click", () => {
      const open = header.classList.toggle("nav-open");
      toggle.setAttribute("aria-expanded", String(open));
      toggle.setAttribute("aria-label", open ? "Close menu" : "Open menu");
    });
  }

  /* 3. Scroll-driven elevator.
     The cabin rises from G (ground) to 4 as the page scrolls top to bottom.
     Landings sit at quarter steps of the travel, so the floor readout matches the cabin. */
  const well = $(".shaft__well");
  const cabin = $(".shaft__cabin");
  const readout = $("[data-floor]");
  const floors = ["G", "1", "2", "3", "4"];
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  let ticking = false;

  function paintShaft() {
    ticking = false;
    if (!well || !cabin) return;
    const scrollable = document.documentElement.scrollHeight - window.innerHeight;
    const p = scrollable > 0 ? Math.min(1, Math.max(0, window.scrollY / scrollable)) : 0;
    const travel = well.clientHeight - cabin.offsetHeight;
    cabin.style.transform = `translate3d(0, ${(1 - p) * travel}px, 40px)`;
    well.style.transform = `rotateY(${-14 + 10 * p}deg)`;
    if (readout) readout.textContent = floors[Math.round(p * 4)];
  }
  function requestPaint() {
    if (!ticking) {
      ticking = true;
      window.requestAnimationFrame(paintShaft);
    }
  }
  if (well && cabin && !reduceMotion) {
    window.addEventListener("scroll", requestPaint, { passive: true });
    window.addEventListener("resize", requestPaint);
    paintShaft();
  } else if (readout) {
    readout.textContent = "G";
  }

  /* 4. Reveal on scroll */
  const reveals = $$(".reveal");
  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.isIntersecting) {
            e.target.classList.add("in");
            io.unobserve(e.target);
          }
        });
      },
      { threshold: 0.12 }
    );
    reveals.forEach((el) => io.observe(el));
  } else {
    reveals.forEach((el) => el.classList.add("in"));
  }

  /* 5. Enquiry forms */
  // Indian mobile: 10 digits starting 6–9, optional +91 / 91 prefix (spaces and dashes already stripped)
  const PHONE_RE = /^(\+?91)?[6-9]\d{9}$/;

  function buildMessage(d) {
    return [
      `New ${d.form || "website"} enquiry`,
      `Name: ${d.name}`,
      `Phone: ${d.phone}`,
      `Location: ${d.location || "-"}`,
      `Building type: ${d.building || "-"}`,
      `Service required: ${d.service || "-"}`,
      d.message ? `Details: ${d.message}` : null,
    ]
      .filter(Boolean)
      .join("\n");
  }

  $$("form[data-enquiry]").forEach((form) => {
    const status = $(".form-status", form);
    const btn = $('button[type="submit"]', form);
    const loadedAt = Date.now();

    const say = (html, ok) => {
      status.innerHTML = html;
      status.style.color = ok ? "var(--ok)" : "var(--err)";
    };

    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const raw = Object.fromEntries(new FormData(form).entries());

      // Spam checks: a filled honeypot or a submit within 2.5s of load is treated as a bot.
      // Bots get a silent success so they do not retry.
      if (raw.website || Date.now() - loadedAt < 2500) {
        say("Thank you. We have received your enquiry.", true);
        form.reset();
        return;
      }

      const phone = String(raw.phone || "").replace(/[\s-]/g, "");
      if (!PHONE_RE.test(phone)) {
        say("Please enter a valid 10-digit mobile number.", false);
        return;
      }

      const data = {
        form: form.dataset.enquiry,
        name: String(raw.name || "").trim(),
        phone,
        location: String(raw.location || "").trim(),
        building: raw.building || "",
        service: raw.service || "",
        message: String(raw.message || "").trim(),
        page: location.pathname,
      };

      btn.disabled = true;
      say("Sending your enquiry…", true);

      // With an endpoint: send to the backend (email notification), fall back to WhatsApp on failure
      if (SITE.formEndpoint) {
        let sent = false;
        try {
          const res = await fetch(SITE.formEndpoint, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(data),
          });
          sent = res.ok;
        } catch (err) {
          sent = false;
        }
        btn.disabled = false;
        if (sent) {
          form.reset();
          say("Thank you. We have your enquiry and will contact you on the number you gave.", true);
          return;
        }
        const link = `https://wa.me/${SITE.whatsappNumber}?text=${encodeURIComponent(buildMessage(data))}`;
        say(`We could not send the form. <a href="${link}" target="_blank" rel="noopener">Send it on WhatsApp instead</a>.`, false);
        return;
      }

      // No endpoint yet: open WhatsApp with the details filled in
      const link = `https://wa.me/${SITE.whatsappNumber}?text=${encodeURIComponent(buildMessage(data))}`;
      window.open(link, "_blank", "noopener");
      btn.disabled = false;
      form.reset();
      say("WhatsApp is opening with your details. Press send there to reach us.", true);
    });
  });
})();
