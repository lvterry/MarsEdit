const slides = [...document.querySelectorAll(".slide")];
const controls = [...document.querySelectorAll(".carousel-control")];
const slidesContainer = document.querySelector(".slides");
const showcase = document.querySelector(".showcase");
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const previousKey = "ArrowLeft";
const nextKey = "ArrowRight";
const autoplayDelay = 5000;
const slideChange = Object.freeze({
  automatic: "automatic",
  keyboard: "keyboard",
  pointer: "pointer"
});

let currentIndex = 0;
let autoplayTimer;

function showSlide(index, change = slideChange.automatic) {
  const animate = change !== slideChange.keyboard;
  currentIndex = index;
  slidesContainer.classList.toggle("is-instant", !animate);

  slides.forEach((slide, slideIndex) => {
    const isCurrent = slideIndex === index;
    slide.classList.toggle("is-active", isCurrent);
    slide.setAttribute("aria-hidden", String(!isCurrent));
  });

  controls.forEach((control, controlIndex) => {
    const isCurrent = controlIndex === index;
    control.setAttribute("aria-current", String(isCurrent));

    if (isCurrent && change === slideChange.keyboard) {
      control.focus();
    }
  });

  if (!animate) {
    requestAnimationFrame(() => {
      slidesContainer.classList.remove("is-instant");
    });
  }
}

function stopAutoplay() {
  window.clearTimeout(autoplayTimer);
}

function scheduleAutoplay() {
  stopAutoplay();

  if (document.hidden || reducedMotion.matches) {
    return;
  }

  if (showcase.matches(":hover") || showcase.contains(document.activeElement)) {
    return;
  }

  autoplayTimer = window.setTimeout(() => {
    const nextIndex = (currentIndex + 1) % slides.length;
    showSlide(nextIndex);
    scheduleAutoplay();
  }, autoplayDelay);
}

controls.forEach((control, index) => {
  control.addEventListener("click", () => {
    showSlide(index, slideChange.pointer);
    scheduleAutoplay();
  });

  control.addEventListener("keydown", (event) => {
    if (event.key !== previousKey && event.key !== nextKey) {
      return;
    }

    event.preventDefault();

    const direction = event.key === nextKey ? 1 : -1;
    const nextIndex = (index + direction + controls.length) % controls.length;
    showSlide(nextIndex, slideChange.keyboard);
  });
});

showcase.addEventListener("pointerenter", stopAutoplay);
showcase.addEventListener("pointerleave", scheduleAutoplay);
showcase.addEventListener("focusin", stopAutoplay);
showcase.addEventListener("focusout", (event) => {
  if (showcase.contains(event.relatedTarget)) {
    return;
  }

  scheduleAutoplay();
});

document.addEventListener("visibilitychange", scheduleAutoplay);
reducedMotion.addEventListener("change", scheduleAutoplay);
scheduleAutoplay();
