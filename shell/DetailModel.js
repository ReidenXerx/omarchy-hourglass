// DetailModel.js -- what Hourglass may say about what you did inside an app, from its window title, with no Qt in
// it so node can test it.
//
// A raw title is never kept. It is turned here into a short label people would recognise ("YouTube", "GitHub:
// basecamp/omarchy", "omarchy-dusk" in Zed) and only that label goes to the helper. Browsers give their site; a page
// is added only for sites you chose. Private windows and password managers give nothing, ever.

var LABEL_MAX = 60

var BROWSERS = ["brave-browser", "firefox", "chromium", "google-chrome", "zen", "vivaldi-stable", "librewolf",
                "org.mozilla.firefox", "com.brave.browser", "microsoft-edge", "epiphany", "org.gnome.epiphany"]
var EDITORS = ["dev.zed.zed", "zed", "code", "code-oss", "vscodium", "cursor"]
var TERMINALS = ["foot", "kitty", "alacritty", "com.mitchellh.ghostty", "org.wezfurlong.wezterm", "dev.warp.warp",
                 "org.gnome.console", "konsole", "xterm"]
var NEVER = ["bitwarden", "1password", "org.keepassxc.keepassxc", "keepassxc", "seahorse", "org.gnome.seahorse"]

// The site at the end of a page title, as browsers and sites write it. Order matters: specific before general.
var SITES = [
  [/ - YouTube$/, "YouTube"],
  [/ at .*Nexus - Mods and Community$/, "Nexus Mods"],
  [/ - Nexus Mods$/, "Nexus Mods"],
  [/ : r\/[A-Za-z0-9_]+$/, "Reddit"],
  [/ - Reddit$/, "Reddit"],
  [/ \/ X$/, "X"],
  [/ - Gmail$/, "Gmail"],
  [/ - Google (Docs|Sheets|Slides|Drive)$/, "Google $1"],
  [/ - Stack Overflow$/, "Stack Overflow"],
  [/ - Wikipedia$/, "Wikipedia"],
  [/ \| Claude$/, "Claude"],
  [/ - Claude$/, "Claude"],
  [/ - Twitch$/, "Twitch"],
  [/ \| Netflix$/, "Netflix"]
]

function lower(s) { return String(s || "").toLowerCase() }

function clip(s) {
  var out = ""
  var raw = String(s || "")
  for (var i = 0; i < raw.length && out.length < LABEL_MAX; i++) {
    var c = raw.charCodeAt(i)
    if (c >= 32 && c !== 127) out += raw[i]
  }
  out = out.replace(/\s+/g, " ").trim()
  return out.length >= LABEL_MAX ? out.slice(0, LABEL_MAX - 1).trim() + "…" : out
}

function kind(appClass) {
  var c = lower(appClass)
  if (NEVER.indexOf(c) >= 0) return "never"
  if (BROWSERS.indexOf(c) >= 0) return "browser"
  if (EDITORS.indexOf(c) >= 0) return "editor"
  if (TERMINALS.indexOf(c) >= 0) return "terminal"
  return "other"
}

// A browser title without the browser's own name; null for a private window, which is never described.
function pageTitle(title) {
  var t = String(title || "")
  if (/(Private Browsing|Incognito|\(Private\)|Private Window|- Private)\s*$/i.test(t)) return null
  return t.replace(/\s+[-—–]\s+(Brave|Mozilla Firefox|Firefox|Chromium|Google Chrome|Zen Browser|Vivaldi|LibreWolf|Microsoft Edge|Web)\s*$/, "")
}

// { site, page } for a page title. GitHub writes its repository first ("owner/repo: description · GitHub" or
// "GitHub - owner/repo: description"); most sites end with their name.
function site(page) {
  var p = String(page || "")
  var gh = /^GitHub - ([\w.-]+\/[\w.-]+)/.exec(p) || /^([\w.-]+\/[\w.-]+)(?:[:·]| at | · ).*GitHub$/.exec(p) || /^([\w.-]+\/[\w.-]+) · GitHub$/.exec(p)
  if (gh) return { site: "GitHub", page: gh[1] }
  if (/ · GitHub$|^GitHub$/.test(p)) return { site: "GitHub", page: p.replace(/ · GitHub$/, "") }
  for (var i = 0; i < SITES.length; i++) {
    var m = SITES[i][0].exec(p)
    if (m) return { site: SITES[i][1].replace("$1", m[1] || ""), page: p.slice(0, m.index) }
  }
  // Otherwise the last short " - " or " | " part, when there is one, is very likely the site.
  var parts = p.split(/ [|—–-] /)
  if (parts.length >= 2) {
    var last = parts[parts.length - 1].trim()
    if (last.length >= 2 && last.length <= 30) return { site: last, page: parts.slice(0, -1).join(" - ") }
  }
  return { site: "", page: p }
}

// Zed and VS Code put the project in the title: "file — project" or "file - project - Visual Studio Code".
function project(appClass, title) {
  var t = String(title || "").replace(/\s+[-—–]\s+(Visual Studio Code|VSCodium|Cursor|Code - OSS)\s*$/, "")
  var parts = t.split(/ [—–-] /)
  return parts.length >= 2 ? parts[parts.length - 1].trim() : (lower(appClass).indexOf("zed") >= 0 ? t.trim() : "")
}

// The label for a window, or "" for none. `pageSites` are the sites whose pages you chose to keep.
// Terminals are not described from their title here: the helper reads what runs in them.
function label(appClass, title, pageSites) {
  var k = kind(appClass)
  if (k === "never" || k === "terminal" || k === "other") return ""
  if (k === "editor") return clip(project(appClass, title))
  var page = pageTitle(title)
  if (page === null) return ""
  var s = site(page)
  if (!s.site) return "Other sites"
  var keep = (Array.isArray(pageSites) ? pageSites : []).indexOf(s.site) >= 0
  return clip(keep && s.page ? s.site + ": " + s.page : s.site)
}

function isPrivate(appClass, title) {
  return kind(appClass) === "browser" && pageTitle(title) === null
}

// "YouTube, GitHub" from the settings, as a checked list.
function siteList(text) {
  return String(typeof text === "string" ? text : "").split(",").map(function (s) { return clip(s) })
    .filter(function (s) { return s.length > 0 && s.length <= 30 }).slice(0, 24)
}
