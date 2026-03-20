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

const ageInput = document.getElementById("age-input");
const ageValue = document.getElementById("age-value");
const reserveMonths = document.getElementById("reserve-months");
const reserveYears = document.getElementById("reserve-years");
const riskFill = document.getElementById("risk-fill");
const riskScore = document.getElementById("risk-score");
const riskCopy = document.getElementById("risk-copy");

const updateQuote = () => {
  if (!ageInput) return;

  const age = Number(ageInput.value);
  const baseMonths = 10000 / 5; // payout / premium
  const loadFactor = 1 + (age - 60) * 0.02;
  const runwayMonths = Math.round(baseMonths / loadFactor);
  const runwayYears = (runwayMonths / 12).toFixed(1);
  const risk = Math.min(100, Math.round(35 + (age - 60) * 3.5));

  ageValue.textContent = age;
  reserveMonths.textContent = runwayMonths;
  reserveYears.textContent = runwayYears;
  riskFill.style.width = `${risk}%`;
  riskScore.textContent = `${risk}%`;

  if (risk < 50) {
    riskCopy.textContent = "Plenty of reserve runway — keep debit orders humming and we're golden.";
  } else if (risk < 75) {
    riskCopy.textContent = "Reserve pressure building. Consider nudging this member for voluntary top-ups.";
  } else {
    riskCopy.textContent = "High risk. Flag for retention script + manual review of beneficiary data.";
  }
};

if (ageInput) {
  ageInput.addEventListener("input", updateQuote);
  updateQuote();
}
