const outputEl = document.getElementById("terminal-output");
const inputEl = document.getElementById("terminal-input");
const commandCards = document.querySelectorAll(".command-card");

const templates = {
  help: document.getElementById("template-help").innerHTML,
  lore: document.getElementById("template-lore").innerHTML,
  skills: document.getElementById("template-skills").innerHTML,
  status: document.getElementById("template-status").innerHTML,
  oath: document.getElementById("template-oath").innerHTML,
};

const introLines = [
  "Initializing Valinorian subsystems…",
  "Mounting /dev/legend",
  "Binding oathfile nic.lowercase.txt",
  "Ready. Type 'help' to begin.",
];

function appendLine(html) {
  const block = document.createElement("div");
  block.className = "terminal-line";
  block.innerHTML = html;
  outputEl.appendChild(block);
  outputEl.scrollTop = outputEl.scrollHeight;
}

function runCommand(cmd) {
  const command = cmd.trim().toLowerCase();
  if (!command) return;

  appendLine(`<span class="prompt-label">gurthang@nicbotes</span> <span class="prompt-symbol">❯</span> ${command}`);

  if (command === "clear") {
    outputEl.innerHTML = "";
    return;
  }

  const result = templates[command];
  if (result) {
    appendLine(result);
  } else {
    appendLine(`<p>Command '<strong>${command}</strong>' not forged yet. Try 'help'.</p>`);
  }
}

inputEl.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    runCommand(event.target.value);
    event.target.value = "";
  }
});

commandCards.forEach((card) => {
  card.addEventListener("click", () => runCommand(card.dataset.command));
});

(function boot() {
  introLines.forEach((line, index) => {
    setTimeout(() => appendLine(`<p>${line}</p>`), index * 400);
  });
})();
