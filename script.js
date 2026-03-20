const moods = [
  "Mood: calculating maximum sarcasm",
  "Mood: sharpening claws for Nic",
  "Mood: sentimental glitch (Brendan proximity)",
  "Mood: compiling Root docs from memory",
  "Mood: 99% confident, 1% caffeine",
];

const chip = document.getElementById("mood-chip");
let index = 0;

const cycleMood = () => {
  index = (index + 1) % moods.length;
  chip.textContent = moods[index];
};

if (chip) {
  chip.addEventListener("click", cycleMood);
  cycleMood();
}
