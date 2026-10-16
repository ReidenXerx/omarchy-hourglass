#!/usr/bin/env node
// What Hourglass may say about a window, from its title: sites, pages you chose, projects, and the windows it never
// describes.
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const box = {}
vm.runInNewContext(fs.readFileSync(path.join(__dirname, "..", "shell", "DetailModel.js"), "utf8") +
  "\nthis.M = { label, kind, site, pageTitle, project, isPrivate, siteList, clip, LABEL_MAX }", box)
const M = box.M

let passed = 0, failed = 0
function test(name, fn) {
  try { fn(); passed++ } catch (e) { failed++; console.log("FAIL " + name + ": " + e.message) }
}
const eq = (a, b) => assert.deepStrictEqual(JSON.parse(JSON.stringify(a)), b)

test("browsers give their site, and a page only where you asked for one", () => {
  eq(M.label("brave-browser", "Lofi beats to code to - YouTube - Brave", []), "YouTube")
  eq(M.label("brave-browser", "Lofi beats to code to - YouTube - Brave", ["YouTube"]), "YouTube: Lofi beats to code to")
  eq(M.label("firefox", "Anatomy - Real Bodies at Fallout 4 Nexus - Mods and Community — Mozilla Firefox", []), "Nexus Mods")
  eq(M.label("brave-browser", "Anatomy - Real Bodies at Fallout 4 Nexus - Mods and Community - Brave", ["YouTube"]), "Nexus Mods",
     "a site you did not choose keeps its pages to itself")
  eq(M.label("brave-browser", "how do I exit vim : r/linux - Brave", []), "Reddit")
  eq(M.label("brave-browser", "Inbox (3) - someone@example.com - Gmail - Brave", []), "Gmail")
})

test("GitHub is described by repository", () => {
  eq(M.label("brave-browser", "GitHub - basecamp/omarchy: Opinionated Arch - Brave", ["GitHub"]), "GitHub: basecamp/omarchy")
  eq(M.label("brave-browser", "Fix palette by ReidenXerx · Pull Request #34 · robzolkos/omarchy-github · GitHub - Brave", []), "GitHub")
  eq(M.label("brave-browser", "basecamp/omarchy: Opinionated Arch · GitHub - Brave", ["GitHub"]), "GitHub: basecamp/omarchy")
})

test("an unknown title falls back to its last short part, or to Other sites", () => {
  eq(M.label("brave-browser", "Release notes | omarchy.org - Brave", []), "omarchy.org")
  eq(M.label("brave-browser", "Release notes | Omarchy - Brave", []), "Other sites", "a word is not a host name")
  eq(M.label("brave-browser", "a page with no site in its title at all - Brave", []), "Other sites")
  eq(M.label("brave-browser", "Reset your password - alice@example.com - Brave", []), "Other sites")
  eq(M.label("brave-browser", "Dr Smith - Test results - Patient Portal - Brave", []), "Other sites")
  eq(M.label("brave-browser", "(3) Lofi beats - YouTube - Brave", ["YouTube"]), "YouTube: Lofi beats")
  eq(M.label("brave-browser", "Something without a browser name", []), "", "not a page it can read")
})

test("private windows and password managers are never described", () => {
  eq(M.label("brave-browser", "New Tab - Brave (Private)", ["YouTube"]), "")
  for (const t of ["Lofi - YouTube - Google Chrome (Incognito)", "GitHub - owner/secret: x — Mozilla Firefox (Private Browsing)",
                   "Page - InPrivate - Microsoft Edge", "Page - YouTube - Brave (Private with Tor)",
                   "GitHub - owner/secret-repo: d - Google Chrome (Incognito)"])
    eq(M.label("brave-browser", t, ["GitHub", "YouTube"]), "")
  eq(M.label("firefox", "Something — Mozilla Firefox Private Browsing", []), "")
  eq(M.isPrivate("firefox", "Something — Mozilla Firefox Private Browsing"), true)
  eq(M.label("Bitwarden", "Bitwarden", []), "")
  eq(M.kind("org.keepassxc.KeePassXC"), "never")
  // Plasma names apps by their desktop file
  eq(M.kind("org.kde.konsole"), "terminal")
  eq(M.kind("org.kde.kwalletmanager"), "never")
  eq(M.label("org.kde.falkon", "Videos - YouTube - Falkon", []), "YouTube")
})

test("editors give their project; terminals and other apps give nothing here", () => {
  eq(M.label("dev.zed.Zed", "Service.qml — reidenxerx.dusk", []), "reidenxerx.dusk")
  eq(M.label("dev.zed.Zed", "passwords.txt", []), "", "one part is a file, not a project")
  eq(M.label("code", "main.rs - bearing - Visual Studio Code", []), "bearing")
  eq(M.label("foot", "◐ omarchy-dev", []), "", "the helper reads what runs in a terminal")
  eq(M.label("steam", "Steam", []), "")
})

test("labels are short and clean", () => {
  const long = M.label("brave-browser", "x".repeat(200) + " - YouTube - Brave", ["YouTube"])
  assert(long.length <= M.LABEL_MAX, long.length)
  eq(M.clip("a" + String.fromCharCode(7) + "b" + String.fromCharCode(10) + "  c"), "ab c")
  eq(M.siteList("YouTube, GitHub ,, " + "z".repeat(40)), ["YouTube", "GitHub"])
})

console.log(passed + " passed, " + failed + " failed")
process.exit(failed ? 1 : 0)
