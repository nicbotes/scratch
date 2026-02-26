const rituals = {
  mind: [
    {
      title: "Window gaze",
      body: "Stand up, look as far as your eyes can focus, and count five slow breaths while naming what you see.",
      link: "https://www.nytimes.com/guides/well/how-to-meditate"
    },
    {
      title: "Sentence swap",
      body: "Rewrite the last anxious thought as a curious question in your notes app. Close it. Carry the question instead.",
      link: "https://psyche.co/guides/how-to-reframe-unhelpful-thoughts"
    },
    {
      title: "Micro gratitude",
      body: "List three mundane things you love in your space. Whisper thanks to each like a weirdo. It works.",
      link: "https://www.ted.com/talks/david_steindl_rast_want_to_be_happy_be_grateful"
    },
    {
      title: "Tab audit",
      body: "Close every browser tab that isn’t needed for the next hour. Say out loud what matters now.",
      link: "https://zenhabits.net/simple-living-online"
    }
  ],
  body: [
    {
      title: "Shoulder reset",
      body: "Roll shoulders back, interlace fingers behind you, and lift for 20 seconds. Release with a sigh.",
      link: "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6029519/"
    },
    {
      title: "Sip + stretch",
      body: "Drink half a glass of water while stretching calves against a wall. Hydration plus fascia love.",
      link: "https://www.health.harvard.edu/staying-healthy/stretching-the-truth"
    },
    {
      title: "Box breath",
      body: "Inhale for 4, hold 4, exhale 4, hold 4. Repeat three cycles. Watch the tension drop.",
      link: "https://www.clevelandclinic.org/health/treatments/box-breathing"
    },
    {
      title: "Palming",
      body: "Rub hands together fast, cup them over eyes for 20 seconds. Reset the screen stare.",
      link: "https://www.aoa.org/healthy-eyes/eye-and-vision-conditions/computer-vision-syndrome"
    }
  ],
  space: [
    {
      title: "Light shift",
      body: "Tilt a lamp so it grazes the wall, not your face. Instant mood filter.",
      link: "https://www.architecturaldigest.com/story/how-light-affects-mood"
    },
    {
      title: "Sound reset",
      body: "Play a 90-second field recording (rain, coffee shop, waves). Let your room borrow another atmosphere.",
      link: "https://mynoise.net/"
    },
    {
      title: "Tidy triangle",
      body: "Pick any three objects on your desk and line them up with intention. Order equals calm.",
      link: "https://www.apartmenttherapy.com/fast-cleaning-tips-367126"
    },
    {
      title: "Scent cue",
      body: "Crack a window or mist the air with citrus. Teach your brain that this smell = focus.",
      link: "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3612440/"
    }
  ]
};

const cards = document.querySelectorAll(".card");
const shuffleBtn = document.getElementById("shuffle");

function pickRandom(items) {
  const idx = Math.floor(Math.random() * items.length);
  return items[idx];
}

function hydrateCards() {
  cards.forEach((card) => {
    const channel = card.dataset.channel;
    const payload = pickRandom(rituals[channel]);
    const titleEl = card.querySelector(".card-title");
    const bodyEl = card.querySelector(".card-body");
    const linkEl = card.querySelector(".card-link");

    if (!payload) return;

    titleEl.textContent = payload.title;
    bodyEl.textContent = payload.body;
    linkEl.href = payload.link;
  });
}

function animateCards() {
  cards.forEach((card, index) => {
    card.classList.remove("card--active");
    setTimeout(() => {
      card.classList.add("card--active");
    }, index * 80);
  });
}

shuffleBtn.addEventListener("click", () => {
  hydrateCards();
  animateCards();
});

hydrateCards();
animateCards();
