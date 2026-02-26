const moods = [
  { text: "Barry is at 'Spreadsheet Contemplation'.", level: 38 },
  { text: "Barry reports 'Mildly Amused Internally'.", level: 47 },
  { text: "Barry entered 'Quantum Seriousness'.", level: 82 },
  { text: "Barry is in 'Snack Line Philosopher' mode.", level: 55 },
  { text: "Barry approaches 'Almost a Smile'. Remain calm.", level: 63 }
];

const facts = [
  "Barry once debugged a server by staring at it until it apologized.",
  "Barry's resting heart rate syncs with fluorescent lighting hum.",
  "Barry owns three identical black shirts labeled Weekday, Meeting, Apocalypse.",
  "Barry's emotion wheel is just a perfect circle labeled 'Focus'.",
  "Barry invented 'passive enthusiasm' so he could appreciate things quietly."
];

const moodOutput = document.getElementById("mood-output");
const factOutput = document.getElementById("fact-output");
const meter = document.getElementById("mood-meter");
const moodBtn = document.getElementById("mood-btn");
const factBtn = document.getElementById("fact-btn");
const smileScore = document.getElementById("smile-score");
const boostBtn = document.getElementById("boost-btn");
const boostNote = document.getElementById("boost-note");

const random = (items) => items[Math.floor(Math.random() * items.length)];

moodBtn.addEventListener("click", () => {
  const payload = random(moods);
  moodOutput.textContent = payload.text;
  meter.style.width = `${payload.level}%`;
});

factBtn.addEventListener("click", () => {
  factOutput.textContent = random(facts);
});

boostBtn.addEventListener("click", () => {
  const boost = (Math.random() * 3).toFixed(1);
  const current = parseFloat(smileScore.textContent);
  const next = Math.min(100, current + parseFloat(boost));
  smileScore.textContent = `${next.toFixed(1)}%`;
  boostNote.textContent = `Boost attempt recorded. Net smile delta: +${boost}%.`;
});
