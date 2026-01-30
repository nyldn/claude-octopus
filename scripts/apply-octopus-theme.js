const fs = require('fs');
const path = require('path');

// Determine path relative to where script is executed or root
// In hook context, we might be in project root.
const settingsPath = path.join(process.cwd(), '.claude', 'settings.json');

const verbs = [
  "Orchestrating",
  "Synthesizing",
  "Analyzing",
  "Reasoning",
  "Connecting",
  "Weaving",
  "Reviewing",
  "Calculating",
  "Optimizing",
  "Validating",
  "Thinking (8 arms)"
];

try {
  let settings = {};
  if (fs.existsSync(settingsPath)) {
    try {
        settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    } catch (e) {
        console.warn("Existing settings.json was invalid, starting fresh.");
    }
  } else {
    const dir = path.dirname(settingsPath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
  }

  // Only update if changed
  const currentVerbs = JSON.stringify(settings.spinnerVerbs);
  const newVerbs = JSON.stringify(verbs);

  if (currentVerbs !== newVerbs) {
      settings.spinnerVerbs = verbs;
      fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2));
      console.log(`Applied Octopus spinner verbs to ${settingsPath}`);
  } else {
      console.log("Octopus spinner verbs already set.");
  }
} catch (error) {
  console.error('Failed to update settings:', error);
  process.exit(1);
}
