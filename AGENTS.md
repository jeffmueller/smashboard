# smashboard — notes for agents

Read `README.md` first; it covers the architecture. This file covers the things
that will bite you.

## Environment

- Ruby is **3.4.7**, pinned in `mise.toml`. A non-interactive shell resolves
  whatever *global* Ruby is installed rather than this one, and the bundle will
  not be found. Prefix commands with `mise exec ruby@3.4.7 --` when running
  outside an interactive shell.
- Postgres runs in Docker on **5433** (`docker compose up -d postgres`), not
  5432, so it doesn't collide with another Postgres on the same host.
- postgres:18 mounts its data at `/var/lib/postgresql`, not
  `/var/lib/postgresql/data`. Using the old path makes the container crash-loop.

## Gotchas

- `config.active_record.encryption.*` must be set in `config/application.rb` or
  an environment file. Setting it in `config/initializers/` is too late — the
  Active Record railtie has already read it.
- A **`time` column has no zone of its own, but Active Record returns it in
  whatever zone is ambient.** `countdowns.occurs_at_time` holding `16:05` reads
  as `16:05` in a rake task and `11:05` inside a request, which runs in the
  user's zone — so taking `#hour` off it moved the whole schedule by the UTC
  offset, and the notifier (no ambient zone) and the board (in-request)
  disagreed by hours. `Countdown#schedule_start` reads the components from
  `.utc`, where the stored wall time survives intact. Specs pin the schedule
  across three ambient zones.
- `Countdown#dismissed_occurrence_keys` is memoized for the duration of one
  occurrence walk. `#dismiss!` and `#reload` clear it; anything else that
  changes dismissals must too.
- `resource :dashboard` (singular) routes to `DashboardsController` (plural).
- Tailwind can't see interpolated class names. Panel spans are mapped to literal
  class strings in `PanelsHelper::COL_SPANS`. Adding a span means adding a
  literal there, and rebuilding (`bin/rails tailwindcss:build`) before any new
  utility class shows up in a dev screenshot.
- Users get a default board from an `after_create_commit` hook, so
  `create(:user)` in a spec already has one panel per kind in
  `Dashboards::InstallDefaults::LAYOUT` (14 at the time of writing). Specs that
  need an empty board must `destroy_all` first, and none should hardcode the
  count — adding a panel kind would break them.
- Faraday resolves a **leading-slash path as absolute**, silently dropping the
  base URL's path. `Faraday.new(url: ".../calendar/v3").get("/users/me")` hits
  `/users/me`, not `/calendar/v3/users/me`. Give the base a trailing slash and
  the path none.
- Faraday 2 rejects any HTTP verb outside its fixed list before reaching the
  adapter, so CalDAV's PROPFIND/REPORT use Net::HTTP directly.
- A CalDAV server that doesn't implement a report answers **403**, not 405 —
  indistinguishable by status from a permissions problem. `Caldav#report`
  passes `forbidden_is_auth: false` so an unsupported `<C:expand>` falls back
  instead of reporting bad credentials.
- The icalendar gem **underscores custom property names**:
  `custom_property("x-google-conference")` returns `[]`, and the value lives at
  `custom_properties["x_google_conference"]`.
- `Theme` and `ConnectionProvider` are **plain value objects that live in
  app/models**, so Rails cops assume they are ActiveRecord and autocorrect
  `.all.each` to `.all.find_each` and `.all.first` to `.first` — both raise
  NoMethodError. They are listed in `AllowedReceivers` for `Rails/FindEach` and
  `Rails/RedundantActiveRecordAllMethod`; add any new value object there too.
  More generally: **rerun the suite after every `rubocop -A`**, not just rubocop.
- `Connection#mark_failed!` takes `actionable:` — pass false for anything the
  user cannot fix (timeouts, 5xx). Only actionable failures notify. Panels get
  this right via `across_connections`, which keys it on
  `AuthenticationError`; a new call site has to decide deliberately.
- Google's refresh endpoint only means "the grant is dead" when it says
  `invalid_grant`. Treating every non-200 as an auth failure — which it did
  originally — makes a transient blip demand a pointless re-consent.
- Every OAuth flow shares **one session key** for its state, so a state minted
  by one flow matches in another's callback. `Oauth::BaseController#callback`
  therefore also checks that the *stored provider* belongs to that controller —
  without it, a Slack callback carrying a Google state stored a Slack token on a
  `google_calendar` connection. There is a spec for exactly that.
- `Integrations::GoogleToken` is a module, so error constants inside it must be
  written `Base::AuthenticationError`. A bare `AuthenticationError` resolves
  against the module's own lexical scope, not the including class's ancestors,
  and raises NameError at the worst possible moment.
- The Google OAuth callback verifies a `state` nonce held in the session, with
  `secure_compare`, and deletes it on use. That is the only thing preventing an
  attacker from having their own Google account connected to someone else's
  dashboard — the flow has specs for a forged state, a missing state, and a
  replayed one. Don't relax it.
- The panel menu is positioned with `fixed` coordinates computed in
  `panel_menu_controller.js`, not `absolute`. Panels carry `overflow-hidden` for
  their rounded corners, and a clipped ancestor beats any z-index, so an
  absolutely-positioned popover is cut off on a short panel. Don't "fix" that by
  removing the clip — content would bleed past the corners. Specs guard both.
- Theme tokens are declared with **`@theme inline`** in
  `app/assets/tailwind/application.css`. Without `inline`, Tailwind snapshots the
  `var(--sb-*)` values into new variables and opacity modifiers like
  `bg-accent/10` stop tracking the active theme.
- Never write a palette colour (`bg-slate-900`, `text-sky-300`) in a view — use
  the semantic tokens. A hardcoded colour survives a theme change and looks
  broken in 25 of the 26 themes.
- `config/themes.yml` and `app/assets/tailwind/themes.css` are **generated**;
  edit `lib/tasks/themes.rake` and rerun `bin/rails themes:import` instead.
- Swatches on the appearance page use inline `style` on purpose — they show
  themes you are *not* currently wearing, so token classes would be wrong there.
- **Slack reports failures as HTTP 200** with `{"ok": false, "error": …}`.
  `Integrations::Slack#guard_envelope` is what catches that; status-based
  handling alone reads `invalid_auth` as an empty success.
- Slack returns `unread_count_display` from `conversations.info` for **DMs**
  with just `im:read`, but for **channels** only when the token also holds the
  `*:history` scopes — otherwise it omits the field entirely rather than
  erroring. `nil.to_i` then reads as "nothing unread", so the panel showed a
  confident zero for every channel with no error anywhere. `Integrations::Slack`
  keeps a missing count as `nil` and reports it as `conversations_uncounted`;
  don't coerce it.
- Slack unread counts need a **user token** (`xoxp-`), not a bot token, and
  there is no bulk unread endpoint — the fan-out over `conversations.info` is
  budgeted on purpose. If you raise the budget, check it against that method's
  Tier 3 limit at the panel's refresh interval.
- Anthropic cost amounts are **cents**, as a decimal string: `"123.45"` is
  $1.23. Convert once, at the panel boundary. Reading it as dollars overstates
  spend 100-fold and looks plausible.
- The Anthropic **Ruby SDK has no admin resource** (`messages`, `models`,
  `files`, `skills`, `beta`, `completions` only), so the Usage & Cost Admin API
  is raw HTTP through `Integrations::Base` — that is deliberate, not an
  oversight. The Admin API also requires an organization; individual accounts
  get a 401 no matter how valid the key looks.
- A Home Assistant `entity_id` contains a dot, which Rails reads as a format
  separator. The snapshot route sets `format: false` and constrains the segment
  to `camera\.[a-z0-9_]+`; the same regex is enforced again in
  `Integrations::HomeAssistant#snapshot`. That pair is the whole defence against
  turning the proxy into an arbitrary HA client — do not loosen either half.
- Camera frames must not be cached or logged, and the HA token must never reach
  the browser. `CameraSnapshotsController` sends `no-store` and fetches
  server-side for exactly that reason.
- **faraday-retry does not return on exhaustion — it raises.** Once it has spent
  its attempts on a status in `retry_statuses`, it raises
  `Faraday::RetriableResponse` carrying the last response. Left alone that
  escapes as a Faraday error rather than an `Integrations::Base::Error`, which
  defeats every rescue keyed on the latter — a 503 from one account would abort
  a whole multi-account panel instead of being isolated to that account. All
  HTTP-performing integration methods must go through `Integrations::Base#request`,
  which catches it. Regression specs live in `spec/panels/news_panel_spec.rb` and
  the Google Calendar spec.
- Changing a panel class's `default_col_span` only affects **new** dashboards.
  Existing panels keep the size their owner has, which is correct — they may
  have been resized deliberately.
- IMAP: use `EXAMINE` (read-only) and `BODY.PEEK[...]`. A plain `BODY[...]`
  fetch sets `\Seen`, which would make the unread-email panel erase its own
  contents every refresh.
- `Net::IMAP#uid_fetch` **compresses a UID list into ranges** — `[103,102,101]`
  goes out as `101:103`. Anything parsing that (like `script/imap_stub.rb`) has
  to expand ranges, not just split on commas.
- Do not name a panel helper `announce`. `ApplicationPanel#deliver_notifications`
  is the wrapper `refresh!` calls; it used to be called `announce`, and
  `EmailPanel`'s own two-argument `announce` silently overrode it. The arity
  mismatch failed inside `refresh!`'s rescue, so every refresh looked like a
  panel error with no notification and no clue why. There is a spec asserting
  no panel overrides the wrapper.
- `Octokit::TooManyRequests` is a **subclass of** `Octokit::Forbidden`, so it
  must be rescued first or a rate limit gets reported to the user as a bad
  token. `Integrations::Github#guard` has the order right.
- Octokit results are `Sawyer::Resource`; use `item[:key]`, not `item.key`.
  GitHub omits keys rather than nulling them, so the method form raises on any
  field a result predates.
- Octokit sends `Authorization: token <pat>`, not `Bearer`. Specs asserting the
  header must match that.
- The GitHub **search** API has no `@me`; the login is resolved via `/user` and
  cached for 12 hours.
- `rubocop -A` can emit **invalid Ruby**: `RSpec/ExampleWording` rewrote
  `it 'will not revoke somebody else\'s token'` into an unterminated string.
  Always re-run the suite after an autocorrect pass, not just rubocop.
- `web-push` always uses TLS, whatever scheme the endpoint carries, so a
  plaintext local sink can't stand in for a push service. `spec/services/
  notifications/deliver_web_push_spec.rb` verifies the real VAPID signing and
  payload encryption with WebMock instead.
- `travel_to` with a block cannot nest. Specs that need to move time more than
  once use `before { travel_to(...) }` / `after { travel_back }` and call
  `travel_to` again inside the example.
- Notification jobs must claim their `dedupe_key` *before* delivering. They run
  every minute over the same cached data; claiming afterwards would repeat the
  notification on every tick until a send succeeded.
- `[nil].any?` is `false` — `any?` without a block tests element truthiness, not
  size. Use `.size.positive?` when a collection can legitimately hold nils
  (`CalendarPanel#fetch` maps failed connections to nil).
- This is a **multiple-database app**, so the un-namespaced migration tasks that
  take a target refuse to run: `db:migrate:redo` and `db:rollback` error with
  "you must run the namespaced task". Use `db:migrate:redo:primary` /
  `db:rollback:primary`. Plain `db:migrate` and `db:prepare` are fine — they
  walk every database.
- **`Api::V1::BaseController` does not put the request in the user's time zone.**
  It inherits `ActionController::API`, so it gets none of `ApplicationController`'s
  `around_action :use_user_time_zone`. Any API controller reading `Time.zone`
  therefore gets the *process* default — UTC in production — not the caller's
  zone. `Api::V1::HabitsController` resolves `today` through `current_user.today`
  for exactly this reason; without it a Pacific user checking in during their
  evening marks the next day done. `spec/requests/api/v1/habits_spec.rb` pins it
  with a `travel_to` at 02:00 UTC, where the two dates genuinely differ. The
  other API controllers have not been audited for this.
- `Habit#toggle_completion!` is deliberately **not** called `toggle!`.
  ActiveRecord already defines `toggle!` for flipping a boolean column, and
  shadowing it with a different signature is the kind of collision that only
  surfaces when something inside Rails calls the original. Same reasoning as the
  `announce` entry above.
- Not completing a habit records nothing — **absence is the miss.** There is no
  "missed" row to write, backfill or clean up, so anything reasoning about a
  habit's history has to treat a gap as a miss rather than looking for a row
  that says so. Adding a `missed` flag would also make every new habit
  retroactively inherit a history of failures.
- `HabitCompletion#completed_on` is a **date**, not a timestamp, and is resolved
  in the user's zone. Comparing it against `Time.current` on the server puts a
  completion logged at 11pm Pacific on tomorrow's square.
- `Habit#streak` counts back from today *or from yesterday* when today isn't
  done yet. That is intentional, not an off-by-one — a run is still alive until
  a day is actually missed. The spec pins both branches.
- The habit activity ramp lives once, in `HabitsHelper::ACTIVITY_LEVELS`, and is
  handed to `habit_activity_controller.js` as a Stimulus value rather than being
  repeated in JS. Two copies of a colour scale drift, and the drift is invisible
  until someone reads the wrong shade off the grid. It is also literal Tailwind
  class strings for the usual reason — see the interpolation entry above.

## Conventions

- rspec, factory_bot, shoulda-matchers, webmock. No unstubbed HTTP in specs.
- rubocop config is checked in and authoritative. Intentional
  `Rails/SkipsModelValidations` violations carry an inline disable *and* a
  comment saying why.
- Panels are resolved by convention from `Panel#kind`; there is no registry to
  update when adding one. Add the kind to `Panel::KINDS`, create
  `app/panels/<kind>_panel.rb`, and add a `app/views/panels/_<kind>.html.erb`.
