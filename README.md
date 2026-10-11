# smashboard

A command center for everything going on in your life: unread mail, today's
meetings, countdowns, todos, habits, bookmarks, GitHub, Slack, breaking news,
weather and cameras on one rearrangeable board.

Multiuser Rails app, installable as a PWA, and API-first so native clients can
be layered on later without reimplementing anything.

![The smashboard dashboard, with panels for meetings, mail, GitHub, todos,
countdowns and breaking news](docs/dashboard.png)

*No real accounts in that screenshot: the local panels come from `db/seeds.rb`
and the rest from the stub servers in `script/`, which is how the board can be
brought up end to end without connecting anything.
See [Developing without credentials](#developing-without-credentials).*

## Getting started

*Just want to run it?* See [Running it with Docker](#running-it-with-docker) —
one compose file, no Ruby needed. What follows is the setup for working on the
code.

You need **Ruby 3.4.7** and **Docker**. The Ruby version is pinned in
`mise.toml`, so [mise](https://mise.jdx.dev) will install it for you
(`mise install`); rbenv, asdf or a system Ruby of the same version work too.

```bash
docker compose up -d postgres     # Postgres 18, published on :5433
bundle install

cp .env.example .env
bin/rails db:encryption:init      # paste the three keys into .env
bin/rails smashboard:vapid        # paste the VAPID keys into .env too

bin/rails db:prepare db:seed
bin/dev                           # web + tailwind watcher + job worker
```

Then sign in at http://localhost:3000 as `dev@smashboard.local` / `password`.
The seeds give that account a full board, so there is something to look at
before you connect anything real.

**Fill in `.env` before `db:prepare`.** The encryption keys and the VAPID pair
are read at boot, and the two generator commands only print them — they don't
write the file. An empty `.env` will boot, but stored credentials can't be
encrypted and notifications are skipped with a log line.

**Run `bin/dev`, not `bin/rails server`.** `db:prepare` creates three databases
— the app's own plus Solid Queue's and Solid Cable's — because development
mirrors production here on purpose: jobs run in a separate worker process so
recurring tasks actually fire, and Action Cable is database-backed so a Turbo
Stream broadcast from that worker reaches the browser. A bare
`bin/rails server` gets you a dashboard that never refreshes itself and never
notifies.

Postgres is published on **5433** rather than 5432 so it won't collide with a
Postgres you may already be running. To use a different port, change it in
`compose.yaml` and set `SMASHBOARD_DATABASE_PORT` to match.

`bin/setup` does the install-and-prepare steps in one go if you'd rather, but
it won't fill in `.env` for you.

## Tests, linting, hooks

```bash
bundle exec rspec
bundle exec rubocop
bundle exec lefthook install -f   # rubocop on staged Ruby, pre-commit
```

The suite is hermetic — WebMock is on and `config/environments/test.rb` sets
fixed encryption keys, so it needs no credentials and runs on a fresh clone.
CI runs the same two commands plus Brakeman, bundler-audit and an importmap
audit.

## Getting around

Every destination — countdowns, todos, habits, bookmarks, connections,
notifications, API tokens, appearance, account and sign-out — sits behind the
one button at the top right. It closes on Escape (handing focus back to the
button), on a click outside, and before Turbo caches the page, so going back
never paints a menu hanging open. The item for the page you're on is marked
`aria-current="page"`.

The time and date sit centred in the same bar, on every page rather than in a
tile on the board. They are rendered server-side first so there is no blank
frame, then ticked in the browser — the server never re-renders once a second.
The zone is the user's own, not the device's, so a phone in another timezone
still shows the board's time.

## Arranging the board

Each panel's header carries a menu with four named widths and a hide action.
The widths are named rather than free-resize because the board is a four-column
grid — `small` (1), `medium` (2), `large` (3) and `full` (4) are the values that
tile without leaving a ragged gap. `Panel#size` maps between the name and
`col_span`; an unrecognised name is ignored rather than producing a broken span.

The menu itself is positioned in **viewport coordinates**, not with `absolute`.
Panels clip their own content to keep their rounded corners, and a clipped
ancestor beats any z-index — an absolutely-positioned menu is simply cut off on a
short panel. Measuring on open also lets it flip above the button when there
isn't room below, rather than opening off the bottom of the window.

Resizing redraws that one tile over Turbo. Hiding removes it and refreshes the
strip of hidden panels at the foot of the board, where one click puts it back —
that one reloads, because the tile isn't in the DOM to replace and where it
belongs depends on its position among the others.

Hiding sets `enabled: false`, which also takes the panel out of `/api/v1/dashboard`
and stops the refresh scheduler working on it, so a hidden panel costs nothing.

Order is drag-and-drop by the header, persisted per user. Nothing about the
layout is shared between accounts.

## Account and sign-in

`/account` splits the two kinds of change:

- **Profile** — first name, last name, time zone, postal code. No password
  challenge, because none of it is a credential.
- **Email and password** — both go through Devise's `update_with_password`, so
  the current password is required. Changing a password rotates the session, so
  the user is re-signed-in rather than bounced to the login screen for
  succeeding.

Devise's own account editor redirects here. Its sign-in, sign-up and password
reset screens are generated into `app/views/devise` and use a separate centred
`auth` layout — signed out there is no dashboard chrome worth showing, and no
stored theme preference either, so those pages follow the operating system.

**Time zone is the user's, everywhere.** Requests run inside
`Time.use_zone(current_user.zone)`, and the places that resolve a date outside a
request — the daily dedupe key for a failing connection, a countdown's schedule
start — use `user.zone` explicitly rather than the worker's clock.

## Theming

The whole UI is drawn from **twelve semantic tokens** — `canvas`, `surface`,
`raised`, `line`, `ink`, `ink-muted`, `ink-faint`, `accent`, `ok`, `warn`,
`danger`, `info` — exposed as Tailwind utilities (`bg-surface`, `text-ink-muted`,
`border-line`). No view names a palette colour, so a theme is a set of CSS
variables and nothing else.

```bash
bin/rails themes:import      # regenerate from the Omarchy themes on your machine
```

That reads `colors.toml` from `/usr/share/omarchy/themes` and
`~/.config/omarchy/themes` and writes two checked-in files: `config/themes.yml`
(what the picker reads) and `app/assets/tailwind/themes.css` (a block of custom
properties per theme). **The server never touches Omarchy at runtime** — a
server that has never heard of it serves the same themes. (A *browser* on an
Omarchy desktop can follow the live theme; see below.)

The importer does real work rather than copying values across:

- Omarchy names background steps relative to a dark palette and light themes
  don't follow that naming, so surfaces are ordered by **measured luminance**.
  Dark themes get a page darker than their panels; light themes get the
  opposite, so panels read as raised either way.
- Themes that declare only one background (some ship a single background plus an
  ANSI palette) have the remaining steps **derived** rather than being dropped.
- `line` is derived by mixing surface toward the text. Taking it from the
  theme's `selection` looked tempting but a selection highlight is meant to be
  loud — one theme sets it to a near-white blue that made a terrible hairline.
- Body contrast is measured per theme and reported; a spec fails the build if any
  theme drops below **4.5:1** against its own canvas.

**Following the system costs no JavaScript and cannot flash.** When a user has
no explicit choice the layout renders *no* `data-theme` attribute at all, and the
stylesheet's `prefers-color-scheme` block decides. An explicit choice renders the
attribute, which wins by specificity.

Picking a theme at `/appearance` repaints the page immediately — the preview is
the whole dashboard, not a swatch — and saving persists it per user.

### Following your Omarchy desktop

On an Omarchy machine, `/appearance` → **Follow my Omarchy theme on this device**
takes the desktop's palette live — `omarchy theme set` recolours the board a
moment later, cross-faded — and Omarchy's look with it: no rounded corners, the
terminal's JetBrainsMono Nerd Font (already installed; nothing is downloaded),
Hyprland's 10px gaps, borders instead of shadows, and the 2px accent border on
the panel under the pointer, as on the focused window.

A web page can't read `~/.local/state`, so this needs the small local bridge
that Notey, Sprocket, Docket, Rocket and OHF@#K already share —
`notey-omarchy-theme` on `127.0.0.1:47613`, installed from
`~/Code/Sites/notey/integrations/omarchy` (`./install.sh`). It allows
`https://smashboard.fsrvr.com` and `http://localhost:3000`. The first time,
Chromium asks whether the site may access apps on this device; allow it.

- **Per device, not per account.** It lives in that browser's localStorage, so a
  phone or a machine without the bridge keeps the account's theme, and the
  account's theme is untouched while following.
- `app/javascript/omarchy_theme.js` maps the palette to the twelve tokens by the
  importer's rules, so following a theme looks like picking it would. It is
  painted inline on `<html>` (outranking every `[data-theme]` block) along
  with `data-face="omarchy"`, which the face rules in `application.css` key on.
- `layouts/_omarchy_boot` paints the cached tokens before first paint, on every
  layout, so a reload never flashes the account's theme first.
- Everything from the bridge is untrusted: only six-digit hex values under the
  twelve known token names reach the page.

### Adding a theme by hand

Drop a `colors.toml` in `~/.config/omarchy/themes/<name>/` and rerun the task, or
add an entry to `config/themes.yml` directly and regenerate the stylesheet. Every
token in `Theme::TOKENS` must be present; the specs check that.

## Connecting your real accounts

Every integration is a **Connection** added at `/connections`. Most take a
credential you create by hand and paste in; Google and Slack instead sign you in
over OAuth, which needs an app registered with the platform first — see
**Setting up the platform apps** below.

**The app tells you this too.** `/connections/new` shows a picker of what you can
connect, and choosing one renders only that provider's fields, each with a hint
saying what it is and where to get it. The catalogue behind that lives in
`ConnectionProvider::CATALOG` — adding an integration means adding an entry
there, and the form needs no changes. The table below is the same information in
one place.

| Panel | Provider | Credential | Where to get it |
|---|---|---|---|
| Meetings | `caldav` | App password | Fastmail → Settings → Privacy & Security → App passwords, scope **CalDAV**. URL `https://caldav.fastmail.com/dav/` |
| Meetings | `google_calendar` | *Sign in with Google* | Needs `GOOGLE_CLIENT_ID`/`SECRET` in `.env` and the callback URL registered — see below |
| Email | `imap` | App password | Fastmail, iCloud, Outlook, anything speaking IMAP. Leave host blank — it's inferred from the address |
| Email | `gmail` | *Sign in with Google* | Same OAuth client as Calendar. Uses `gmail.readonly`, not IMAP's full-mail scope |
| GitHub | `github` | Personal access token | github.com → Settings → Developer settings → PAT. Scopes: `notifications`, `repo` (private repos only) |
| Slack | `slack` | *Sign in with Slack* | Needs `SLACK_CLIENT_ID`/`SECRET` and the redirect URL registered — see below. One connection per workspace |
| Weather | `nws` | *none* | No key. Uses your profile postal code, or set `latitude`/`longitude`. Set `NWS_USER_AGENT` in `.env` |
| Weather | `weather_station` | Tempest token | tempestwx.com → Settings → Data Authorizations → create a personal access token. Leave `station_id` blank to use the first station |
| Cameras | `home_assistant` | Long-lived access token | HA → your profile → Security → Long-lived access tokens. `base_url` is your HA address, e.g. `http://homeassistant.local:8123` |
| Breaking news | `news_feed` | Shared password | Any server answering `GET /api/breaking-news`. Set the feed URL, plus the cookie name if it isn't `auth` |

Then turn on notifications at `/notification_settings` — generate VAPID keys
first (`bin/rails smashboard:vapid`) or delivery is skipped with a log line.

### Setting up the platform apps

Two of the ten providers need an app registered with the platform before anyone
can connect: **Google** — one client covers both Calendar and Gmail — and
**Slack**. Everything else (GitHub, IMAP, CalDAV, Home Assistant, Tempest,
Anthropic, the news feed) is a credential you create directly, and NWS needs nothing at
all. You do each of these once, however many accounts connect later.

#### Google — one project, one OAuth client

1. **console.cloud.google.com** → create a project.
2. **APIs & Services → Library** → enable **Google Calendar API** *and*
   **Gmail API**. Both, separately.
3. **APIs & Services → OAuth consent screen** → *External* (unless you are on
   Workspace) → add yourself, and anyone else who will use this instance, under
   **Test users**. It also wants an app homepage, a privacy policy and a terms
   of service, all on the app's own domain and reachable signed out:

       https://your-host/          https://your-host/privacy          https://your-host/terms

   All three are served by this app; see **Privacy policy and terms** below.
4. **Credentials → Create credentials → OAuth client ID → Web application** →
   authorized redirect URI `https://your-host/oauth/google/callback`
   (`http://localhost:3000/oauth/google/callback` in development).
5. Put the client ID and secret in `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`.

Both *Gmail* and *Google Calendar* then work from the connection picker; they
share the client and differ only in the scopes requested.

Three things that catch people:

- **Enabling an API is separate from creating the client.** Skip step 2 and
  sign-in still succeeds — then the first API call fails with "this API has not
  been used in this project". The error surfaces on the panel rather than at
  sign-in, which makes it look unrelated to the setup you just did.
- **Testing status issues refresh tokens that expire after 7 days.** That is
  Google's policy about the consent screen, not about how the token was
  obtained, so no amount of plumbing avoids it. *In production* removes it.
- **Gmail's scopes are restricted**, so going *In production* means a Google
  security assessment. For personal use that's unnecessary — but it does mean
  Gmail realistically stays on the 7-day cycle. If that grates, an `imap`
  connection with a Gmail app password needs no app at all and never expires.

#### Slack — one app per instance

Slack ties **every** token type to an app, and the legacy token generator is long
gone, so there is no way to get a user token without one. It takes about five
minutes and needs no review or submission.

1. **api.slack.com/apps → Create New App → From scratch**. Name it, pick a
   workspace.
2. **OAuth & Permissions → Redirect URLs** → add
   `https://your-host/oauth/slack/callback`.
3. Same page, **User Token Scopes** — *not* Bot Token Scopes — add
   `channels:read`, `groups:read`, `im:read`, `mpim:read`, plus
   `channels:history`, `groups:history`, `im:history`, `mpim:history` — the
   history scopes are what make Slack return an unread count for channels.
4. **Basic Information → App Credentials** → put the client ID and secret in
   `SLACK_CLIENT_ID` and `SLACK_CLIENT_SECRET`.

You do **not** need to press *Install to Workspace* — signing in through
smashboard performs the install. Connecting a second workspace later is just the
Sign in button again.

#### If other people will use your instance

Both platforms get stricter once someone connects an account you don't own:

- **Slack** needs *Manage Distribution* enabled before the app can be installed
  outside its home workspace, and workspaces where that person isn't an admin
  may require admin approval.
- **Google** requires each person to be listed under **Test users** while the
  consent screen is in Testing — 100 maximum.

GitHub has neither constraint: everyone creates their own personal access token.

### How a Google connection behaves

Picking Gmail or Google Calendar sends you straight to Google; the callback
stores the refresh token and labels the connection with the account's email. If
the client credentials are missing, the button explains what's absent and names
the exact callback URL to register, rather than bouncing you to a broken Google
page.

Two request parameters do the real work and are easy to leave out:
`access_type=offline`, without which Google issues no refresh token at all, and
`prompt=consent`, without which a *second* authorization of an already-granted
account comes back without one. Both are asserted by specs.

**The token refresh is already invisible.** The access token Google actually
accepts lasts an hour and is renewed from the stored refresh token inside the
panel's own background job, cached per connection, with no user involvement ever.
What cannot be automated is getting a *new refresh token* once a grant dies —
that needs a human at Google's consent screen, by design. No background job can
click it.

What is automated is everything around that:

- Only `invalid_grant` is treated as a dead grant. A 5xx, a timeout or any other
  error is transient, so a bad minute at Google no longer sends you through a
  re-consent that fixes nothing.
- A failure the user cannot act on **does not notify**. The panel still shows the
  error, but nothing wakes anyone for a timeout.
- A failure they *can* act on links straight into the authorization flow, so
  fixing it from the push notification is one tap rather than a navigation.
- Connections record when they were last authorized, so a grant quietly dying on
  a 7-day cycle is visible rather than mysterious.

**Publishing status still matters.** A consent screen left in *Testing* with an
external user type issues refresh tokens that **expire after 7 days** — that is
Google's policy about the consent screen, not about how the token was obtained,
so the button doesn't avoid it. Set the consent screen to *In production* for a
token that lasts. Until then, a lapsed grant shows the connection as failing,
fires the once-a-day connection warning, and offers a one-click **Reconnect** on
the connections page.

The requested scopes are `calendar.readonly` and `userinfo.email` — read-only,
and only enough identity to name the connection.

### How the Slack connection behaves

Slack shares `Oauth::BaseController` with Google. Two things about it differ:

- The authorize request sends **`user_scope`**, not `scope`. `scope` asks for a
  *bot* token, and a bot's unread count is not yours. The resulting token
  arrives nested under `authed_user`, not at the top level.
- There is **no refresh token**. A Slack user token is long-lived unless the app
  has token rotation switched on, so nothing expires on a timer the way Google's
  Testing-mode grants do.

One connection per workspace — signing in again with a different workspace adds a
second rather than replacing the first.

### Gmail

Gmail rides the **same Google OAuth client** as Calendar; the scopes come from
whichever provider is being connected. It uses the Gmail API rather than IMAP
with XOAUTH2, deliberately: IMAP needs `https://mail.google.com/`, which also
grants send and delete, while this needs only **`gmail.readonly`**. A panel that
counts unread messages has no business holding permission to delete them.

The API also hands over a ready-made `snippet` per message, so none of the MIME
decoding the IMAP client does is needed. Both clients normalise to the same
shape, so `EmailPanel` renders either without knowing the difference — you can
have a Fastmail IMAP mailbox and a Gmail account side by side.

The default search is `is:unread in:inbox`; the `query` setting takes any Gmail
search, so `is:unread in:inbox -category:promotions` works.

Note that Gmail scopes are **restricted** by Google: a published app serving
external users needs a security assessment. For personal use — you and a few
people added as test users — that doesn't apply, but it does mean the 7-day
Testing-mode token expiry is the practical ceiling unless you go through
verification.

### Known gaps before you rely on it

- **The Tempest client has never run against a real station** — it's written to
  the documented API and covered by specs, but only the API host and its 401
  shape were checked live.
- **Email is read-only** and always will be at this layer: the IMAP client opens
  mailboxes with `EXAMINE` and peeks at bodies, so nothing it does can mark mail
  read.
- A failing connection shows on the panel *and* fires a notification once a day,
  so a bad token announces itself rather than silently zeroing a count.

## Architecture

### Panels

A `Panel` is one tile on a user's board. Every panel class lives in
`app/panels/` and is resolved by convention — `Panel#kind` of
`github_pull_requests` finds `GithubPullRequestsPanel`.

Panels come in two flavours, and the distinction drives everything else:

| | Local | Remote |
|---|---|---|
| Examples | countdowns, todos, habits, bookmarks | email, github, slack, news, weather |
| Data source | this app's database | a third-party API |
| Implements | `#build` | `#fetch` |
| When it runs | every render | `RefreshPanelJob`, out of band |
| Declared by | `required_providers` empty | `required_providers` non-empty |

Remote panels never block a page render. `RefreshPanelJob` fetches and writes
to `panels.data`; the dashboard renders whatever was last cached and swaps in
the fresh tile over Turbo Streams when the fetch lands. A failing integration
parks that one panel in an error state — it can't take the board down.

`RefreshStalePanelsJob` (config/recurring.yml, every minute) sweeps enabled
panels and enqueues refreshes for any whose cache has aged past that panel
class's own `refresh_interval`, so panels with different cadences ride one tick.

`Dashboards::InstallDefaults` runs on every dashboard render, not just at
signup, and installs any kind in `LAYOUT` the user has no row for — that's how a
panel added after someone signed up reaches them, since the board has no "add a
panel" control. New kinds land at the end. Hiding a panel keeps its row, so
nothing a user has turned off comes back; destroying a row outright (only
reachable through the API) does mean it reappears.

### Countdowns

Two shapes share one model:

- **One-off** — `target_at` set, `rrule` blank. A concert.
- **Recurring** — `rrule` (RFC 5545) + `occurs_at_time`. Kids home from school.

Recurring countdowns can be waved off for a single iteration. A
`CountdownDismissal` pins the exact occurrence being skipped, so the schedule
rolls straight to the next one and nothing else changes state. Dismissing a
one-off silences it for good — the UI's confirmation text differs accordingly.

Occurrences are matched by UTC epoch second, not by `Time` equality, so
sub-second drift between IceCube's generated occurrences and what Postgres
round-trips can't cause a missed match.

### Claude usage

Claude Code's usage numbers only exist on the machine you run it on: the rate
limits sit behind that machine's OAuth login, and the token counts sit in its
local transcripts under `~/.claude/projects`. A server elsewhere cannot reach
either. So this panel is pushed to rather than fetched from — it is a local
panel with no connection.

`script/smashboard-usage-reporter` runs on each machine, shells out to Omarchy's
`omarchy-agent-usage-claude` collector (which already owns the transcript
formats and the usage endpoint, and puts the access token in an Authorization
header and nowhere in its output), and POSTs the resulting record to
`/api/v1/agent_usage` with an API token. The Anthropic credential never leaves
the machine.

    ./deployment/reporter/install.sh   # on each machine you run Claude Code on

That installs the script, writes `~/.config/smashboard/reporter.env` at mode
600, and enables a user timer that reports every ten minutes. Set
`SMASHBOARD_USAGE_COLLECTOR` to use something other than Omarchy's collector;
anything printing the same JSON will do.

One row is kept per machine per agent, replaced on each push, so the table stays
the size of your hardware rather than growing with snapshots nothing reads. Rate
limits are account-wide, so the panel takes them from the freshest-reporting
machine rather than summing them into a number over 100%; token counts do sum
across machines. A machine silent for more than 30 minutes is shown as stale.

The earlier version of this panel used Anthropic's Usage & Cost Admin API, which
needs an `sk-ant-admin01-…` key and an organization — it is not available to an
individual account, which made it useless for exactly the person this dashboard
is for.

### Privacy policy and terms

`/privacy` and `/terms`, public by design — Google's OAuth consent screen
requires both, and a reviewer opens them from a signed-out browser, so
`LegalController` skips authentication and a spec pins that it stays that way.
They're linked from the sign-in screen and from the header menu.

The wording describes what this app actually reads from each connected service
rather than being generic filler, because that's what a scope review is checking
against, and the privacy policy states Limited Use compliance for Google data by
name. `app/models/legal.rb` holds the facts both documents share — the host, the
last-updated date, and the operator contact — so the two can't drift apart. Set
`LEGAL_CONTACT_EMAIL` to show an address; without it the pages name the operator
instead of printing a dead mailto.

The date is a constant bumped by hand, not derived from the file: it's a claim
about when the terms last changed, and a deploy that touches nothing substantive
shouldn't restate it.

These are boilerplate for a personal installation, not legal advice.

### Habits

Things you mean to do every day, checked off from the panel or from `/habits`.
Local — no integration, nothing fetched, no setup. Like bookmarks, the icon is
an emoji you choose, the first letter of the name stands in when there isn't
one, and the list is drag-orderable.

The data model is one decision and its consequences: **absence is the miss.**
Completing a habit writes a row; not completing it writes nothing. So the table
stays proportional to what actually happened rather than to days elapsed, and
adding a habit today doesn't retroactively invent a history of failures behind
it. There is no "missed" record to keep in sync.

A completion is stored as a **date, not a timestamp**. "Done today" is a claim
about the user's day in their own zone; storing the instant would put a
completion logged at 11pm Pacific on tomorrow's square. Checking off is
idempotent — a double tap on a phone should land where it started rather than
erroring, and the unique index on `(habit_id, completed_on)` would refuse the
second insert anyway.

A **streak counts back from today, or from yesterday when today isn't checked
off yet.** Counting only from today would read zero every morning until you
checked in, which is both discouraging and untrue — the run is still alive until
a day is actually missed.

**Archiving keeps the history.** Retiring a habit hides it from the list without
deleting its completions, so the activity graph doesn't develop holes in its own
past.

The graph itself runs in whole weeks — a column is a week, a row a weekday —
over the last `HabitsPanel::ACTIVITY_WEEKS` of them. Days falling outside the
window are still rendered, as blanks, so the shape stays rectangular instead of
ragged at the corners. A square's intensity is the *share* of that day's habits
completed rather than a raw count, so the ramp means the same thing whether you
keep three habits or ten; anything done at all is at least level 1, so a single
completion never renders as an empty square. Filtering the graph to one habit is
done in the browser from data already on the page, so switching costs no round
trip.

Nothing is signalled by colour alone: a completed habit gets a checked box, a
strikethrough and screen-reader text, and every square in the grid carries a
title naming the date and what was done on it.

Both places that edit a habit — the panel and this page — get one Turbo Stream
response carrying the panel, the list, the form and the flash, on the same
reasoning as bookmarks below.

### Bookmarks

Links to the sites and web apps you want one click away. A local panel — no
integration, nothing fetched, no setup.

Two decisions worth knowing about:

- **The icon is an emoji you choose, not a fetched favicon.** Pulling favicons
  would mean asking a third party for an icon per bookmark on every render,
  which hands them the list of sites you care about. A bookmark with no emoji
  falls back to the first letter of its title, which costs no request and
  themes correctly.
- **URLs are restricted to `http` and `https`.** A `javascript:` or `data:` URL
  executes when the link is clicked, so the scheme is checked against an
  allow-list rather than merely parsed. Anything without a scheme gets
  `https://` prepended — `github.com` is what people actually type — but a
  string that already carries a scheme keeps it, so a dangerous one trips the
  allow-list instead of being quietly rewritten.

Leave the name blank and the site's domain is used, port included when it isn't
the scheme default (`homeassistant.local:8123` and `homeassistant.local` are
different machines).

Manage them at `/bookmarks`, where they can be dragged into the order they
appear on the board. Anything can be added straight from the panel by pasting a
URL into the field at the bottom of the tile.

The emoji picker searches the full Unicode set (1,914 emoji, skin-tone variants
omitted). The list is generated into `app/javascript/emoji_data.js` by
`script/generate_emoji_data.rb` and shipped with the app rather than fetched, so
it works offline and nobody learns which emoji a user browsed. It's 66KB, so the
picker pulls it in with a dynamic `import()` the first time one is opened rather
than on every page that renders a form.

Both places that edit a bookmark — the panel's quick-add and this page — get one
Turbo Stream response carrying updates for the panel, the list, the form and the
flash. A stream aimed at an element the current page doesn't have is ignored, so
one response serves both without knowing where it came from.

### Connections

A `Connection` is one linked external account. Users hold several per provider
(two Slack workspaces, three mailboxes), so panels reference connections by id
rather than by provider. `credentials` is encrypted at rest via
`ActiveRecord::Encryption` and is stripped from `as_json`, so it can't leak
into an API response or an exception report.

Encryption keys come from credentials, or from ENV — see `config/application.rb`.
The ENV path exists so a self-hosted instance can supply keys without shipping
a `master.key`. Tests use fixed keys set in `config/environments/test.rb`, so
the suite is hermetic and CI needs no secrets.

### Authorization

Every record is owned by exactly one user and is reached through
`current_user`'s associations, so a record belonging to somebody else is a 404
rather than a policy failure. There is no policy layer, deliberately — it would
be dead weight until sharing exists.

### API

`/api/v1` mirrors the web app and is authenticated by a bearer `ApiToken`
(`Authorization: Bearer smb_…`). Only the digest is stored; the plaintext is
shown once at creation.

`GET /api/v1/dashboard` returns everything needed to draw the whole board in
one call. Panel payloads are produced by the same presenters the web views
render, so the API and the web UI can't drift.

The local data a client needs to write as well as read has full CRUD:
`/api/v1/panels`, `/api/v1/bookmarks`, `/api/v1/countdowns`, `/api/v1/todos`,
`/api/v1/habits` and `/api/v1/connections`. The three whose order the user drags
— panels, bookmarks and habits — also take `POST .../reorder` with the full list
of ids. `POST /api/v1/habits/:id/toggle` takes an optional `date`, so a client
can fill in yesterday without pretending it is yesterday, and
`POST /api/v1/habits/:id/archive` and `.../unarchive` retire a habit and bring
it back — `?scope=all` on the index is how a client sees the archived ones.

`/api/v1/agent_usage` is the one endpoint that only goes one way: machines push
their Claude Code usage to it because the server cannot fetch that data itself.
See **Claude usage** above.

## Integrations

| Provider | Status | Notes |
|---|---|---|
| Breaking news feed | **Working** | `GET /api/breaking-news`; host and password cookie are both configuration |
| CalDAV (Fastmail) | **Working** | Full discovery walk, server-side recurrence expansion |
| Google Calendar | **Working** | Calendar API v3, refresh-token auth |
| IMAP (Gmail, Fastmail) | **Working** | App-password auth, read-only, host inferred from the address |
| GitHub | **Working** | Notifications + pull requests, PAT auth, GitHub Enterprise supported |
| Slack | **Working** | Unread counts per workspace, user token |
| Claude usage | **Working** | Push-based: machines report their own usage to `/api/v1/agent_usage` |
| Weather (NWS) | **Working** | Alerts, conditions and radar. No API key |
| WeatherFlow Tempest | **Working** | Personal station readings; preferred over NWS conditions |
| Cameras (Home Assistant) | **Working** | Snapshots proxied server-side; no camera credentials needed |

Scaffolded panels declare their providers, refresh interval and payload
contract, and render a placeholder rather than an error. `ApplicationPanel.pending?`
marks them and the refresh sweeper skips them.

### Calendar

Two clients feed one panel, and both normalise to the same event hash so the
panel doesn't care where an event came from.

**CalDAV** (`Integrations::Caldav`) speaks raw Net::HTTP rather than Faraday,
because CalDAV needs PROPFIND and REPORT and Faraday 2 rejects any verb outside
its fixed list. It runs the full discovery walk — `current-user-principal` →
`calendar-home-set` → calendar list — and caches the result for 12 hours, so
only a server URL and an app password are needed. Set `calendar_urls` in the
connection's settings to skip discovery entirely.

Recurring events are expanded **by the server** via `<C:expand>`. That matters:
server-side expansion is the only way to get RECURRENCE-ID overrides right (one
moved instance of a weekly meeting arrives as a separate VEVENT sharing the
master's UID). Servers that reject that form fall back to
`Meetings::RecurrenceExpander`, which honours EXDATE but cannot see overrides.

**Google Calendar** (`Integrations::GoogleCalendar`) uses the v3 API rather than
Google's CalDAV endpoint — `singleEvents=true` expands recurrences server-side,
and `conferenceData` hands over a structured Meet link instead of one that has
to be dug out of a description. Access tokens are cached per connection until a
minute before they expire.

Events the user declined and events marked CANCELLED are dropped by both paths.
The same meeting arriving from two connected accounts is deduplicated on title
plus start minute. If one calendar account fails, the panel still renders the
others and flags itself partial; only every account failing is an error.

### Finding the video call link

`Meetings::VideoLink` is handed every candidate string in priority order —
structured conference field, then location, then URL, then description — and the
first recognised **provider** URL wins. It matches known meeting-URL shapes
(Zoom, Meet, Teams, Webex, Whereby, Jitsi, GoTo, BlueJeans, Chime, Around,
Discord, Slack) rather than "any URL", because a Zoom invite body also contains
a support link, a dial-in page and a one-tap-mobile link, and grabbing the first
URL reliably picks the wrong one.

It decodes HTML entities and lifts URLs out of `href` attributes before
stripping tags, since an Outlook invite renders "Click here to join" and carries
the real URL only in the anchor.

### Email

IMAP with an app password — both Fastmail and Gmail issue those, and neither
needs OAuth for IMAP, so a mailbox can be connected without going near the
Google OAuth flow.
Leave the host blank and it's inferred from the address domain; Gmail, Fastmail,
iCloud, Outlook and Yahoo are recognised.

Two details keep this panel from destroying the thing it reports on:

- **EXAMINE, not SELECT.** The mailbox is opened read-only, so nothing here can
  change message state even by accident.
- **`BODY.PEEK[...]`, not `BODY[...]`.** A plain BODY fetch sets `\Seen` on
  every message it touches — rendering an unread panel with BODY would mark the
  previewed mail read and empty the panel out from under you. There's a spec
  asserting every body fetch item is a PEEK.

The unread count comes from `STATUS`, which answers without opening the mailbox
at all, so a mailbox with nothing unread is never even selected. Previews refetch
the content-type headers alongside a truncated body and stitch them back
together, which lets the `mail` gem do the transfer-encoding and charset work —
quoted-printable, MIME-encoded subjects and HTML bodies all come out as clean
text.

New-mail notifications are wired but **off by default**, since most people don't
want a push per message. When switched on they're capped per refresh, so coming
back from an outage to a full mailbox isn't a firehose, and deduplicated on
Message-ID rather than UID because UIDs don't survive a mailbox resync.

### Breaking news

The news panel reads one endpoint and renders the single top developing story.
It isn't tied to a particular service — the provider is a *contract*, so any
server that answers this can be connected:

```
GET <feed url>/api/breaking-news

{
  "headline": "Something happened",
  "summary": "A paragraph of context.",
  "mentionCount": 9,
  "sources": ["Reuters", "AP"],
  "articles": [
    { "source": "Reuters", "title": "The thing", "link": "https://example.com/a" }
  ]
}
```

`mentionCount` and `sources` describe how widely the story is being carried;
both may be omitted. An empty body is understood as "nothing breaking right
now" rather than as a failure.

If the endpoint is behind a shared password, put the password on the connection
and name the cookie the server expects to read it from — it defaults to `auth`.
Both the feed URL and the cookie name are per-connection settings, so two people
can connect two different feeds, and `NEWS_FEED_BASE_URL` /
`NEWS_FEED_AUTH_COOKIE` supply the fallback for a single-connection instance.
A feed needing no password gets no cookie.

A new headline raises a notification; the same headline on the next refresh
stays quiet, keyed on the headline itself rather than a timestamp.

### Weather

NWS needs **no API key** — only a `NWS_USER_AGENT` naming the app and how to
reach whoever runs it, since anonymous traffic gets throttled.

Location is a latitude/longitude. NWS has no notion of a postal code, so a zip
is geocoded once and cached for 90 days (centroids don't move); explicit
coordinates on the connection skip the lookup. It falls back to the postal code
on the user's profile.

Three things come back per refresh, from a grid point and station list that are
themselves cached hard (30 and 7 days) because they never change:

- **Alerts** from `/alerts/active?point=`, sorted loudest-first by CAP severity.
- **Conditions** from the nearest reporting station. NWS reports SI regardless
  of locale — degC, km/h, Pa — so conversion happens in the client, driven by
  each measurement's own `unitCode` rather than an assumption. A station that
  has gone quiet returns nil conditions rather than costing you the alerts too.
- **Radar**, which turned out to be easy: the grid point names a radar station,
  and `https://radar.weather.gov/ridge/standard/{STATION}_loop.gif` is a public
  animated loop. No key, no embed, no tiles.

Alert notifications respect a **minimum severity** (default `severe`), so a
Tornado Warning wakes you and an Air Quality Alert doesn't, and are marked
`require_interaction` so a warning stays on screen until acknowledged.

#### Your own station

A `weather_station` connection reads a WeatherFlow Tempest through its
`better_forecast` endpoint, authenticated with a personal access token. Leave
`station_id` blank and the first station on the account is used.

That endpoint is preferred over `observations/station/{id}` because it takes
explicit unit parameters — so the reply arrives in the units the panel shows,
rather than whatever the station happens to be configured for — and it carries a
human conditions string and a cardinal wind direction the raw feed doesn't.

When both are connected, **the station wins for conditions** — a sensor in your
garden beats the airport twenty miles away — while alerts and radar always come
from NWS. If the station is unreachable the panel falls back to NWS conditions
and marks itself partial rather than going blank. The station also contributes
readings NWS has no idea about: UV index, rain accumulated today, lightning
strike count and pressure trend.

`vendor` on the connection selects the client (`tempest` is the default), so a
second brand is a new class in `WeatherPanel::STATION_CLIENTS` rather than a
rewrite.

Note: the Tempest client is written against the documented API and covered by
specs, but has not been run against a live station — that needs your token.


### Cameras

Cameras are read through Home Assistant rather than spoken to directly. HA
already holds the per-camera credentials and normalises Reolink, ONVIF and the
rest behind one `camera_proxy` endpoint, so smashboard needs no RTSP handling
and no camera passwords of its own — just a long-lived access token.

**The browser never talks to Home Assistant.** Frames are fetched server-side
by `CameraSnapshotsController` and streamed to the viewer, for two reasons: the
long-lived token would otherwise have to be handed to the client, and HA usually
lives on a home LAN a phone can't reach. Frames are sent `no-store`, since each
one is per-viewer and immediately stale.

The entity id in that URL is the only thing between a URL parameter and an
arbitrary Home Assistant endpoint, so it is pinned twice: a route constraint of
`camera\.[a-z0-9_]+` and the same regex again in the client. A traversal attempt
or a non-camera entity never reaches HA at all. The dot in `camera.front_door`
would otherwise be read as a format separator, which is why the route sets
`format: false`.

Only the camera *list* is cached in the panel payload, and it refreshes every 15
minutes because it changes rarely. The pictures refresh client-side on their own
interval (30s by default, clamped to 5–600), so the panel never re-renders and no
image bytes pass through the panel cache. The refresher pauses on a hidden tab
rather than waking a Raspberry Pi in the background, keeps the last good frame
dimmed when a camera hiccups instead of flashing a broken image, and reports how
many cameras are not responding.

Leave `entity_ids` blank to show every camera HA knows about, or list them to
pick a subset and its order.

### Claude usage

Not an integration — the panel is pushed to by the machines that run Claude
Code, because that is the only place the data exists. See **Claude usage** under
Architecture above, and `deployment/reporter/`.

### Slack

Unread counts per workspace, one connection each. It must be a **user token**
(`xoxp-…`) — unread is a per-person concept, and a bot token would report the
bot's unreads. Scopes: `channels:read`, `groups:read`, `im:read`, `mpim:read`,
`channels:history`, `groups:history`, `im:history`, `mpim:history`.

The history scopes are not about reading messages — they are what makes
`conversations.info` return an unread count for a **channel** at all. Slack
returns unread for DMs on `im:read` alone, so a token without them looks like it
works: every DM counts, and every channel silently reports nothing. The panel
therefore treats a missing count as *uncounted* rather than as zero, and says so
rather than presenting a short number as the whole truth.

**Slack reports failures as HTTP 200 with `{"ok": false, "error": …}`.** Checking
the status alone reads a rejected token as a successful, empty response, so the
envelope is the only signal this client trusts. `missing_scope` replies name the
scope that's absent, and the error message passes that through.

There is no endpoint that returns unread counts in bulk — the tidy one the
desktop client uses is undocumented, so this takes the documented route:
`users.conversations` to list, then `conversations.info` per conversation. That
is an N+1 by construction, so:

- The fan-out is **budgeted** (40 per refresh by default, configurable per
  connection). `conversations.info` is Tier 3 — 50+/minute — and the panel's
  refresh interval keeps the sustained rate well under that.
- **Direct messages are counted first**, since they're the actionable ones and
  there are usually few enough to fit the budget entirely.
- When the budget doesn't cover the workspace the panel says so and shows the
  count as `28+`, rather than presenting a short number as the whole truth.
- Hitting the rate limit mid-count keeps what was counted instead of losing the
  workspace.

Counts use `unread_count_display`, the number Slack badges with — it leaves out
joins, leaves and other noise nobody thinks of as a message. Archived and
**muted** conversations are excluded from the listing: muting a channel is the
user saying they don't want to be nagged about it.

Names are resolved only for the handful of conversations actually shown, so a
workspace with a thousand members doesn't cost a thousand lookups.

### GitHub

Two panels off one connection, authenticated with a personal access token. Set
`api_endpoint` on the connection to a GitHub Enterprise API root to point it at
a private host; blank means github.com, and web links are derived from the
repository's own host so enterprise links don't bounce to github.com.

**Notifications** come from `GET /notifications`. GitHub returns an API URL for
each subject, which has to be rewritten for the browser: `/pulls/42` is
`/pull/42` on the web, `/commits/sha` is `/commit/sha`, and releases,
discussions and check suites have no page at the corresponding path at all — a
release's API id is not its web tag — so those link to the repo section.

**Pull requests** are two search queries, one for `review-requested:` and one
for `author:`, merged with review requests first so that a PR which is somehow
both keeps the relationship that needs action. Review state per PR would mean an
extra API call each, so the panel shows relationship and draft status instead.

Attribute access on octokit results goes through `Sawyer::Resource#[]` rather
than method calls, because GitHub omits keys rather than nulling them —
`item.draft` raises on a result predating the draft field while `item[:draft]`
returns nil.

A new review request fires a notification, deduplicated on the PR URL, so one
sitting in your queue for a week notifies once rather than every refresh.

## Developing without credentials

Six of the integrations have a throwaway stub server, so most of the board can
be brought up without a single real account: CalDAV, GitHub, IMAP, Slack, Home
Assistant and the news feed. Each speaks enough of the real protocol to exercise
the actual client rather than a mock, and each listens on the loopback.

The gaps are deliberate. NWS weather needs no credential, so it already works
untouched. Gmail and Google Calendar are OAuth-only, and a stub convincing
enough to be worth having would have to impersonate Google's consent flow.
Tempest and Anthropic need a real token.

`script/caldav_stub.rb` implements enough of RFC 4791 to walk the real
discovery path:

```bash
ruby script/caldav_stub.rb        # 127.0.0.1:4111
```

Add a `caldav` connection pointing at `http://127.0.0.1:4111/` with any
username and password. It serves two calendars of now-relative events carrying
Zoom, Meet and Teams links.

`script/github_stub.rb`:

```bash
ruby script/github_stub.rb        # 127.0.0.1:4311
```

Add a `github` connection with `api_endpoint` `http://127.0.0.1:4311/` and any
token. It serves `/user`, `/notifications` and `/search/issues` with enough
shape for the real octokit client to parse, including a draft PR and the
release/check-suite subjects whose URLs need special handling.

`script/imap_stub.rb`:

```bash
ruby script/imap_stub.rb           # 127.0.0.1:1143, no TLS
```

Add an `imap` connection with host `127.0.0.1`, port `1143`, `ssl` `false` and
any credentials. It implements enough of RFC 3501 for the real net-imap client —
LOGIN, STATUS, EXAMINE, UID SEARCH and UID FETCH with literal-encoded body
parts — serving a plain text, an HTML and a quoted-printable message so the
decoding paths are all exercised.

`script/slack_stub.rb`:

```bash
ruby script/slack_stub.rb                     # 127.0.0.1:4611
SLACK_BASE_URL=http://127.0.0.1:4611/api bin/dev
```

Serves `auth.test`, `users.conversations`, `conversations.info` and `users.info`
for a workspace of DMs and channels — including Slack's habit of reporting
failures as HTTP 200. Unlike `ANTHROPIC_BASE_URL`, `SLACK_BASE_URL` is not an
official convention; it exists only so this stub can stand in. Leave it unset
everywhere else.

`script/home_assistant_stub.rb`:

```bash
ruby script/home_assistant_stub.rb    # 127.0.0.1:8123
```

Add a `home_assistant` connection with base_url `http://127.0.0.1:8123` and any
token. It serves four camera entities (one deliberately unavailable) plus a
couple of non-camera ones, and generates each frame with a sweep that moves every
second — so a refresh is visibly a refresh rather than a cached image. The frames
are PNGs encoded by hand from zlib and CRC32, so the stub needs no image library.

`script/news_feed_stub.rb`:

```bash
ruby script/news_feed_stub.rb      # 127.0.0.1:4711
```

Add a `news_feed` connection with feed URL `http://127.0.0.1:4711`, cookie name
`auth` and any password. It serves the whole contract in **Breaking news**
above, rotating the headline every 45 seconds so the "only notify when the story
changes" behaviour is visible without waiting for real news, and it rejects a
request with no password cookie so the auth path is exercised too.

## Notifications

What currently fires:

| Kind | Trigger | Configurable |
|---|---|---|
| Meeting reminders | `NotifyUpcomingMeetingsJob`, every minute | Lead time in minutes |
| Countdowns | `NotifyCountdownsJob`, every minute | Lead time in minutes |
| Breaking news | The top headline on the connected feed changes on refresh | On/off |
| Review requests | A new PR appears awaiting your review | On/off |
| New email | A message arrives in a connected mailbox | On/off, off by default |
| Weather alerts | An NWS alert is issued for your area | Minimum severity |
| Connection problems | A connection flips to error | On/off |

New email is off by default; everything else ships on. Every kind listed can
fire; a kind whose panel doesn't exist yet renders greyed out and marked, which
is what `NotificationPreference#available?` is for.

`NotificationPreference` holds per-user, per-kind switches; a missing row means
"use the shipped default", so adding a kind needs no backfill.

**Deduplication is the load-bearing part.** Both notifier jobs run every minute
and rescan the same data, so `Notifications::Deliver` takes a `dedupe_key` and
claims it through a unique index on `notification_deliveries` *before* sending.
Claiming first means a crash mid-send loses a notification rather than repeating
it every minute forever, and two workers racing produce exactly one.

The jobs read the calendar panel's **cached** events rather than calling any
calendar API, so a minute-by-minute scan costs one query and no third-party
traffic. A meeting reminder's notification links straight to the video call when
the event has one.

`Notifications::Deliver` sends Web Push and prunes subscriptions the push
service reports as gone. Generate VAPID keys with `bin/rails smashboard:vapid`
and put them in `.env`; without them delivery is skipped with a log line.

Users turn push on per device from the notifications page — a browser
permission prompt, then the subscription is POSTed to the server. The Stimulus
controller reports refused and blocked permissions distinctly, because those
failure modes are otherwise invisible.

## API tokens

`/api_tokens` mints bearer tokens for `/api/v1`. The plaintext is shown exactly
once, on the page right after creation, and only the digest is stored.

## Running it with Docker

The easiest way to self-host — a NAS, a home server, anything that runs Docker.
Images are published for **linux/amd64 and linux/arm64**, so an ARM NAS pulls
rather than spending an hour compiling native gems.

```bash
mkdir smashboard && cd smashboard
curl -O https://raw.githubusercontent.com/jeffmueller/smashboard/main/docker/compose.yaml

# Generate every key the app needs, in one file
docker run --rm ghcr.io/jeffmueller/smashboard:latest bin/rails smashboard:env > .env

# Set APP_HOST to the name you'll actually reach it on, then:
docker compose up -d
```

Open `http://<APP_HOST>:3000` and create the first account. There is no admin
user and no invite step — the first person to sign up is just a user, and so is
everyone after them.

**Edit `.env` before starting.** Two entries matter more than the rest:

- **`APP_HOST`** is the name you'll browse to. Requests arriving under a
  different `Host` header are refused — that's DNS-rebinding protection, not a
  bug — so `nas.local` and `192.168.1.50` are not interchangeable. Set it to
  whichever you'll actually type.
- **`SMASHBOARD_FORCE_SSL`** decides who is terminating TLS. Left as `false`,
  the app serves plain HTTP, which is what you want on a LAN with nothing in
  front of it. Delete the line if you're putting a reverse proxy in front that
  terminates TLS. Getting this wrong fails *quietly*: with SSL enforced over
  plain HTTP the session cookie is marked `secure`, the browser never sends it
  back, and signing in appears to work and then returns you to the login page.

**Keep the generated `.env`.** Those keys encrypt every credential you store for
a connected account. Rotating them signs everyone out and makes what's already
stored undecryptable — the data is still there, but nothing can read it.

**Two containers, not one.** `web` serves the app; `jobs` runs the Solid Queue
supervisor that does the recurring sweeps and every panel refresh. They're split
so an integration fetch that wedges can't take the web server down with it, and
both are pinned to the same image tag so they can never drift apart. `web` is
what migrates on boot, which is why `jobs` waits for it to become healthy.

Postgres comes up in the stack with a named volume. To use a database you
already run, point `SMASHBOARD_DATABASE_HOST` (and `_PORT`, `_USER`,
`_PASSWORD`) at it and delete the `postgres` service.

To update: `docker compose pull && docker compose up -d`. Migrations run on
boot. `:latest` moves only on a tagged release rather than on every commit to
`main`; pin `SMASHBOARD_TAG` in `.env` if you'd rather choose explicitly.

To build the image yourself instead of pulling — a fork, or an architecture
that isn't published — `docker build -t smashboard .` and point the compose
file's `image:` at it.

## Deployment

`deployment/` holds the scripts this app is actually deployed with: a Raspberry
Pi on the LAN, behind nginx, with Let's Encrypt. They are parameterised, so they
work for any Debian-ish host you can reach over SSH — the target is set in
`deployment/.env.deploy` and nothing about it is baked into the scripts.

    cp deployment/.env.deploy.example deployment/.env.deploy   # set host, user, domain
    ./deployment/setup-pi.sh          # once: databases, services, nginx, SSL
    ./deployment/deploy.sh --migrate  # every time
    ./deployment/check-status.sh      # what's it doing?

**Prerequisites on the Pi:** nginx, PostgreSQL, certbot, and rbenv with Ruby
3.4.7. The DNS record for the domain has to exist before `setup-pi.sh` runs —
it checks, because a failed ACME attempt counts against Let's Encrypt's rate
limit.

**Two services, not one.** `smashboard-web` runs Puma; `smashboard-jobs` runs
the Solid Queue supervisor that does the recurring sweeps and every panel
refresh. Split rather than `SOLID_QUEUE_IN_PUMA` so an integration fetch that
wedges can't take the web server down with it, and so either half restarts
alone.

**Nothing secret is ever shipped.** `deploy.sh` excludes every env file and
`config/master.key`, then greps the finished archive and refuses to upload if
one turns up anyway. The Pi keeps its own `~/smashboard/.env`, generated by
`setup-pi.sh` at mode 600 and never overwritten — `SECRET_KEY_BASE`, the three
Active Record encryption keys, and the VAPID pair are written once. Rotating any
of them has a cost: sessions all sign out, stored connection credentials become
undecryptable, and every push subscription goes silent until each device
re-enables notifications.

**Gems and assets are built on the target**, not on the machine you deploy
from: native extensions and the Tailwind binary are architecture-specific, and
the Pi is usually aarch64 while the machine you work on probably isn't.

**Releases swap rather than merge.** The archive unpacks into a fresh directory
which is then renamed into place, so a file deleted from the repo doesn't live
on forever on the device. The previous release is kept until the new one passes
its health check. `storage/` is a symlink into `shared/`, so uploads survive.
`--migrate` dumps the primary database first and keeps ten of those; the cache,
queue and cable databases aren't dumped because losing them costs a cold cache
and any queued job, not data.

### Things that bit, so they don't again

`config/puma.rb` binds from `PORT` and `BIND_HOST`, and the systemd unit passes
neither `-p` nor `-b`. Passing `-b` as well makes Puma open the port twice and
die on the duplicate with `EADDRINUSE`. `BIND_HOST` defaults to `0.0.0.0` for
development (so a phone on the LAN can install the PWA) and is set to
`127.0.0.1` in production — without that the app answers on the LAN directly,
with nginx and its TLS bypassed entirely.

`assume_ssl` and `force_ssl` are both on, because nginx terminates TLS and Rails
only ever sees plain HTTP on the socket; without `assume_ssl` it would decide
every request was insecure and redirect to https forever. `/up` is excluded from
that redirect — it's what the proxy and any uptime check hit, and a 301 is not a
health signal — and from host authorization, since it's requested over the
loopback by address rather than by name.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and the house conventions, and
[AGENTS.md](AGENTS.md) for the list of things that have bitten — worth reading
before a first change whether or not you use an AI assistant.

Security problems go through [SECURITY.md](SECURITY.md) rather than the issue
tracker: an instance holds live credentials for whatever its owner has
connected.

## License

[MIT](LICENSE). Copyright (c) 2026 Jeff Mueller.
