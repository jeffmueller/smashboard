# Contributing

Thanks for taking a look. This is a personal project published in the hope it's
useful, so please open an issue before starting anything large — it may already
be deliberate, or not something I want to maintain.

## Getting set up

You need Ruby 3.4.7 (pinned in `mise.toml`) and Docker for the development
database.

```bash
docker compose up -d postgres     # Postgres 18, published on :5433
bundle install
cp .env.example .env              # then fill in the keys below
bin/rails db:encryption:init      # paste the three keys into .env
bin/rails smashboard:vapid        # paste the VAPID keys into .env too
bin/rails db:prepare db:seed
bin/dev                           # web + tailwind watcher + job worker
```

The encryption and VAPID keys must be in `.env` **before** `db:prepare` — the
app reads them at boot.

Seeds create `dev@smashboard.local` / `password` with a full board.

Run `bin/dev`, not `bin/rails server`. Jobs run in a separate worker process, so
a server on its own gets you a dashboard that never refreshes and never
notifies.

## Before you open a pull request

```bash
bundle exec rspec
bundle exec rubocop
bundle exec lefthook install -f   # rubocop on staged Ruby, pre-commit
```

Both must be clean. CI runs the same two things plus Brakeman, bundler-audit
and an importmap audit.

## House rules

A few conventions the codebase holds to, which reviews will ask about:

- **No unstubbed HTTP in specs.** WebMock is on; every integration spec stubs
  its endpoints. The suite is hermetic and needs no credentials.
- **Never write a palette colour in a view.** Use the semantic tokens
  (`bg-surface`, `text-ink-muted`, `border-line`) — a hardcoded colour survives
  a theme change and looks broken in 25 of the 26 themes.
- **Re-run the suite after `rubocop -A`**, not just rubocop. Autocorrect has
  produced invalid Ruby here before.
- **Comments explain why, not what.** The existing ones are the house style.
- Adding a panel means adding its kind to `Panel::KINDS`, creating
  `app/panels/<kind>_panel.rb` and `app/views/panels/_<kind>.html.erb`. Panels
  are resolved by convention; there's no registry to update.
- Adding an integration means adding an entry to `ConnectionProvider::CATALOG`
  — the connection form needs no changes.

`AGENTS.md` is worth reading before a first change. It's a list of the things
that have bitten, with the reasoning, and it will save you time whether or not
you use an AI assistant.

## Reporting bugs

Include what you expected, what happened, and the relevant lines from
`log/development.log`. If it involves an integration, say which provider —
their failure modes differ a lot.

Security problems go through the process in [SECURITY.md](SECURITY.md), not the
issue tracker.
