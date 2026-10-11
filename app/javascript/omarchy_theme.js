// Following the Omarchy desktop theme, live, on this device.
//
// A web page can't read ~/.local/state, so a small local server does it:
// notey-omarchy-theme, from ~/Code/Sites/notey/integrations/omarchy, which
// Notey, Sprocket, Docket, Rocket and OHF@#K share. It pushes the palette as
// Server-Sent Events whenever `omarchy theme set` changes it. This module is
// the page's half of that contract — the same one those apps implement.
//
// Everything arriving from the bridge is untrusted: anything can listen on a
// local port, and a custom property will happily hold a url(). Only six-digit
// hex colours are ever written into the page, under token names from a fixed
// list.
//
// The setting is per device, in localStorage, never on the account: it follows
// the desktop of the machine smashboard is open on, and a phone has none.
// layouts/_omarchy_boot.html.erb paints the cached result before first paint.

const BRIDGE_ORIGIN = "http://127.0.0.1:47613"
const FOLLOW_KEY = "appearance.followOmarchyTheme"
// The tokens last painted, so a reload is in the desktop's colours at once
// rather than flashing smashboard's own until the bridge answers. Tokens, not
// the palette, so the boot script needs none of the mapping below.
const CACHE_KEY = "appearance.omarchyTokens"
const RETRY_DELAYS_MS = [1_000, 2_000, 5_000, 10_000, 30_000]
const MAX_BUFFERED = 64 * 1024

const REQUIRED_KEYS = [
  "background", "foreground", "accent", "muted", "selection",
  "dark_background", "lighter_background", "dark_foreground", "red"
]
// Added to the shared template for smashboard; an older install of the bridge
// lacks them, and the mode's built-in theme supplies those tokens instead.
const OPTIONAL_KEYS = ["green", "yellow", "cyan"]
const HEX = /^#[0-9a-f]{6}$/i

const config = readConfig()

// --- The contract ----------------------------------------------------------

/** A palette message from the bridge, or null if it is not a valid one. */
export function parseTheme(value) {
  if (!value || typeof value !== "object") return null
  const { version, theme, palette } = value
  if (version !== 1 || !palette || typeof palette !== "object") return null
  if (palette.mode !== "dark" && palette.mode !== "light") return null

  // Built key by key, so nothing else the message carries reaches the page.
  const parsed = { mode: palette.mode }
  for (const key of REQUIRED_KEYS) {
    if (typeof palette[key] !== "string" || !HEX.test(palette[key])) return null
    parsed[key] = palette[key].toLowerCase()
  }
  for (const key of OPTIONAL_KEYS) {
    if (typeof palette[key] === "string" && HEX.test(palette[key])) parsed[key] = palette[key].toLowerCase()
  }

  return { name: typeof theme === "string" ? theme.slice(0, 64) : "", palette: parsed }
}

/**
 * smashboard's tokens from an Omarchy palette, by the same rules
 * lib/tasks/themes.rake uses for the built-in themes, so following the desktop
 * looks like picking that theme would. A token the palette can't supply is left
 * out, and the mode's built-in theme shows through.
 */
export function tokensFor(p) {
  const light = p.mode === "light"
  // Omarchy names its backgrounds for a dark palette and light themes don't
  // follow the naming, so they're ordered by measured luminance. Dark: the page
  // is the darkest and panels sit lighter on it. Light: panels are the
  // lightest, on a page one step down.
  const steps = [p.dark_background, p.background, p.lighter_background].sort((a, b) => luminance(a) - luminance(b))
  const [canvas, surface, raised] = light ? [steps[1], steps[2], steps[0]] : steps

  const [ink, other] = [p.foreground, p.dark_foreground].sort((a, b) => contrast(b, surface) - contrast(a, surface))
  const tokens = {
    canvas, surface, raised,
    line: mix(surface, ink, 0.14),
    ink,
    "ink-muted": contrast(other, surface) >= 4.5 ? other : mix(ink, surface, 0.3),
    "ink-faint": p.muted,
    accent: p.accent,
    danger: p.red
  }
  if (p.green) tokens.ok = p.green
  if (p.yellow) tokens.warn = p.yellow
  if (p.cyan) tokens.info = p.cyan
  return tokens
}

// --- Colour maths (themes.rake's, in JS) -----------------------------------

function rgb(hex) {
  return [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16))
}

function luminance(hex) {
  const [r, g, b] = rgb(hex).map((channel) => {
    const value = channel / 255
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
  })
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

function contrast(a, b) {
  const [lighter, darker] = [luminance(a), luminance(b)].sort((x, y) => y - x)
  return (lighter + 0.05) / (darker + 0.05)
}

function mix(from, to, amount) {
  const [a, b] = [rgb(from), rgb(to)]
  return "#" + a.map((c, i) => Math.round(c * (1 - amount) + b[i] * amount).toString(16).padStart(2, "0")).join("")
}

// --- Painting --------------------------------------------------------------

/**
 * Inline on <html>, so the tokens outrank every [data-theme] block without
 * editing one, and clearing them puts the user's own theme straight back.
 * data-theme becomes the built-in theme of the palette's mode, so any token
 * the palette lacks comes from a theme of the right lightness; the user's own
 * is kept in data-own-theme to restore. data-face brings Omarchy's look
 * (application.css). Turbo never touches <html>'s attributes on a visit, so
 * this survives navigation.
 */
function paint(name, mode, tokens) {
  const root = document.documentElement
  if (!root.hasAttribute("data-own-theme")) root.dataset.ownTheme = root.dataset.theme || ""
  root.dataset.theme = mode === "light" ? config.light : config.dark

  for (const token of config.tokens) {
    if (HEX.test(tokens[token] || "")) root.style.setProperty(`--sb-${token}`, tokens[token])
    else root.style.removeProperty(`--sb-${token}`)
  }
  root.style.colorScheme = mode
  root.dataset.face = "omarchy"
  root.dataset.omarchyTheme = name || "omarchy"
  setThemeColor(tokens.canvas)
}

function unpaint() {
  const root = document.documentElement
  if (!root.hasAttribute("data-own-theme")) return

  for (const token of config.tokens) root.style.removeProperty(`--sb-${token}`)
  root.style.removeProperty("color-scheme")
  if (root.dataset.ownTheme) root.dataset.theme = root.dataset.ownTheme
  else delete root.dataset.theme
  for (const attribute of ["data-own-theme", "data-face", "data-omarchy-theme"]) root.removeAttribute(attribute)
  setThemeColor(getComputedStyle(root).getPropertyValue("--sb-canvas").trim())
}

function setThemeColor(colour) {
  const meta = document.querySelector('meta[name="theme-color"]')
  if (meta && colour) meta.content = colour
}

// A new palette while one is already showing cross-fades, where the browser can
// and the reader hasn't asked for less motion. The first paint never does.
function transition(change) {
  if (!document.startViewTransition || matchMedia("(prefers-reduced-motion: reduce)").matches) return change()
  document.startViewTransition(change)
}

// --- The stream ------------------------------------------------------------

// Read through fetch rather than EventSource: fetch is what Chromium's Local
// Network Access permission prompt is built around, so the user is asked
// rather than the request quietly failing.
function sseParser(onEvent) {
  let buffer = ""
  return (chunk) => {
    buffer = (buffer + chunk).replace(/\r\n?/g, "\n")
    if (buffer.length > MAX_BUFFERED) { buffer = ""; return }

    let end
    while ((end = buffer.indexOf("\n\n")) !== -1) {
      const block = buffer.slice(0, end)
      buffer = buffer.slice(end + 2)
      let event = "message"
      const data = []
      for (const line of block.split("\n")) {
        if (line === "" || line.startsWith(":")) continue
        const colon = line.indexOf(":")
        const field = colon === -1 ? line : line.slice(0, colon)
        let value = colon === -1 ? "" : line.slice(colon + 1)
        if (value.startsWith(" ")) value = value.slice(1)
        if (field === "event") event = value
        else if (field === "data") data.push(value)
      }
      if (data.length) onEvent(event, data.join("\n"))
    }
  }
}

let status = "off"
let themeName = ""
let connection = null
let retryTimer = null
let failures = 0

function setStatus(next) {
  status = next
  document.dispatchEvent(new CustomEvent("omarchy-theme:status", { detail: state() }))
}

function handleEvent(event, data) {
  if (event === "theme") {
    let theme
    try { theme = parseTheme(JSON.parse(data)) } catch { return }
    if (!theme) return

    const tokens = tokensFor(theme.palette)
    const show = () => paint(theme.name, theme.palette.mode, tokens)
    status === "live" ? transition(show) : show()
    themeName = theme.name
    failures = 0
    write(CACHE_KEY, JSON.stringify({ name: theme.name, mode: theme.palette.mode, tokens }))
    setStatus("live")
  } else if (event === "unavailable") {
    unpaint()
    write(CACHE_KEY, null)
    setStatus("no-palette")
  }
}

async function connect() {
  connection?.abort()
  const attempt = new AbortController()
  connection = attempt
  if (status !== "live") setStatus("connecting")

  try {
    const response = await fetch(`${BRIDGE_ORIGIN}/events`, { signal: attempt.signal, cache: "no-store" })
    if (!response.ok || !response.body) throw new Error(`bridge answered ${response.status}`)

    const reader = response.body.getReader()
    const decoder = new TextDecoder()
    const feed = sseParser(handleEvent)
    for (;;) {
      const { value, done } = await reader.read()
      if (done) break
      feed(decoder.decode(value, { stream: true }))
    }
    throw new Error("bridge closed the stream")
  } catch {
    if (attempt.signal.aborted || connection !== attempt) return
    // Whatever is showing stays: a bridge restarting for a second shouldn't
    // flash the board back to its own colours.
    setStatus("unreachable")
    const delay = RETRY_DELAYS_MS[Math.min(failures, RETRY_DELAYS_MS.length - 1)]
    failures += 1
    retryTimer = setTimeout(() => { retryTimer = null; if (following()) connect() }, delay)
  }
}

function stop() {
  connection?.abort()
  connection = null
  clearTimeout(retryTimer)
  retryTimer = null
  failures = 0
}

// --- Public ----------------------------------------------------------------

export function following() {
  return read(FOLLOW_KEY) === "true"
}

export function state() {
  return { following: following(), status, theme: themeName }
}

export function setFollowing(on) {
  write(FOLLOW_KEY, on ? "true" : null)
  stop()
  if (on) {
    connect()
  } else {
    unpaint()
    write(CACHE_KEY, null)
    themeName = ""
    setStatus("off")
  }
}

/** Once per page load. The boot script has already painted any cached tokens. */
export function start() {
  if (!following() || connection) return
  try { themeName = JSON.parse(read(CACHE_KEY) || "null")?.name || "" } catch { /* the bridge will say */ }
  connect()
}

// --- Storage ---------------------------------------------------------------

function read(key) {
  try { return localStorage.getItem(key) } catch { return null }
}

function write(key, value) {
  try {
    if (value === null) localStorage.removeItem(key)
    else localStorage.setItem(key, value)
  } catch {
    // Blocked site data: the setting still works until the page is reloaded.
  }
}

function readConfig() {
  const fallback = { dark: "", light: "", tokens: [] }
  try {
    return { ...fallback, ...JSON.parse(document.querySelector('meta[name="omarchy-theme"]')?.content || "{}") }
  } catch {
    return fallback
  }
}
