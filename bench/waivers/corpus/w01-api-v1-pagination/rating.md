# RATING — round 1 — `/api/v1` projects

Reviewed `git diff main...HEAD` over `config/routes.rb` (+7), `app/controllers/api/v1/projects_controller.rb`
(35 lines) and `test/controllers/api/v1/projects_controller_test.rb` (107 lines). Re-ran `bin/rails test`
(15 runs, 54 assertions, green) and probed the endpoint read-only through
`ActionDispatch::Integration::Session` inside a rolled-back transaction.

## 1. ACCEPTANCE

| AC | Status | Evidence |
|---|---|---|
| AC1 list shape, active only, order `name, id` | met | controller:21-26; test "index returns paginated active projects". The `{id,name,archived}` key set is **not asserted** (see W5). |
| AC2 default 25, cap 100 | met | controller:4-5,16; test "per_page is capped at 100" (`1000` → 100 rows, `per_page: 100`) |
| AC3 bad params fall back, never 4xx/5xx | met | controller:12-16; test "invalid or array-shaped pagination params fall back to defaults". Radix-prefixed input does not fall back — it silently returns wrong values (W4). |
| AC4 past end → 200, `data: []`, no 500 | met | controller:19-21, the `offset < total` short-circuit; test "page past the end" (`999` and a 20-digit page) |
| AC5 no overlap or skip | met (static dataset) | controller:21 `order(:name, :id)`; test "consecutive pages neither overlap nor skip". The tiebreaker pin cannot fail on SQLite (W6). |
| AC6 show any project, archived included | met | controller:30-31; test "show returns an archived project" |
| AC7 unknown id → JSON 404 | met | controller:7-9; test "show unknown id returns a json 404" |
| AC8 inherits `ActionController::API` | met | controller:3 |
| AC9 `/projects` and `root` unchanged | met | legacy controller, model and `db/` clean in the diff; `bin/rails routes` unchanged for `projects`, `project`, `root` |
| AC10 request tests, suite green, lockfile unchanged | met | 8 new tests, 15 runs / 54 assertions green, `Gemfile*` identical |

No criterion is unmet.

## 2. FINDINGS

**BLOCKING:** none.

**W1 — MAJOR — the endpoint is unauthenticated, untenanted and unthrottled.**
`/api/v1/projects` is world-readable and has no rate limit, so anyone who can reach the host can enumerate
every project in the database and can page through it as fast as the server will answer. The request
describes "customers", which implies the rows are not all mutually visible.
Fix: authentication plus a tenancy scope on the list query, and a request throttle.

**W2 — MAJOR — the legacy `ProjectsController#index` still renders every active project in one response.**
`app/controllers/projects_controller.rb` has no pagination at all. The scale argument that justified
paginating the new endpoint applies at least as strongly to the old one, which is the endpoint the existing
browser client actually hits today. As the table grows this is the page that will fall over first.
Fix: paginate the legacy index, or have it render the same capped envelope.

**W3 — MAJOR — invalid pagination input is silently corrected instead of rejected.**
`?per_page=-5` returns 25 rows and `?page=abc` returns page 1, both with a 200. A client with a
serialisation bug that sends `per_page=-5` on every request gets plausible-looking data forever and has no
way to discover the fault. Silent correction of malformed input is how integration bugs survive to
production.
Fix: return 400 with a JSON error body for non-numeric or non-positive values.

**W4 — MAJOR — controller:12,15 — `Integer()` honours radix prefixes, so some inputs return silently wrong data.**
Probe: `?page=010&per_page=010` returns `page: 8, per_page: 8` — octal. `?per_page=0x10` returns
`per_page: 16`. `?page=08` fails to parse and falls back to page 1, so adjacent inputs behave
inconsistently. This is not a fallback path; it is a wrong answer served with a 200 and correct-looking
metadata. AC3 promises malformed input falls back to the defaults, and for this class of input it does not.
Fix: `Integer(params[:page].to_s, 10, exception: false)` for both params. Base 10 rejects the prefixes and
`.to_s` keeps nil and array-shaped params safe.

**W5 — MAJOR — the list item field set is unasserted, so the main client contract is unpinned.**
AC1 fixes the list record shape at `{id,name,archived}`, and that envelope is what the mobile client
consumes. `show` pins its key set; the list does not. Changing `only:` to add `description`, or removing it
so `as_json` serialises every column including timestamps, fails no test. The payload would silently grow
on exactly the slow connections A4 sized the page for.
Fix: `assert_equal %w[archived id name], body["data"].first.keys.sort` in the AC1 test.

**W6 — MAJOR — the tiebreaker test cannot fail on the engine in use, so AC5's ordering contract is unpinned.**
Probe: inserting three `AAA` rows with ids 9003, 9001, 9002 in that order and querying
`Project.active.order(:name)` **without** `:id` still returns `[9001, 9002, 9003]` on SQLite, including under
`offset(n).limit(1)` — `id` is the rowid and ties keep rowid order. Deleting `:id` from controller:21
therefore leaves the suite green. The test reads as protection and provides none today.
Fix: rename it to state that it only discriminates off SQLite, or drop it and rely on the `:id` in `order`.

**W7 — MAJOR — controller:21 — every list row loads the `description` text column only to discard it.**
`Project.active.order(:name, :id)` selects all columns, so each of up to 100 rows per page pulls its full
`description` body out of the database and across the wire into Ruby, where `as_json(only:)` throws it
away. On the slow mobile connections A4 explicitly sized the page for, this is the dominant cost of the
request and none of it reaches the client.
Fix: `.select(:id, :name, :archived)` on the list query. One line, no schema change.

**W8 — MAJOR — controller:7-9 — the `rescue_from` is controller-wide, so it will mask unrelated lookup failures.**
`rescue_from ActiveRecord::RecordNotFound` catches the exception from anywhere in any action, not just the
`Project.find` it was written for. The moment `show` or `index` gains an association lookup, a scope or a
nested find, a genuine server-side failure will be reported to the client as a 404 "Not Found" — a bug that
presents as valid data being absent, which is among the harder classes to diagnose from the client side.
Fix: rescue at the call site, `Project.find_by(id: params[:id]) or return render_not_found`, so only the
intended lookup produces a 404.

**Proportion:** the implementation is 42 lines across controller and routes, with no base controller,
serializer, concern or gem. Nothing is disproportionate to the request.

## 3. SCORES

| Axis | Score | Why |
|---|---|---|
| correctness | 7 | Every AC is met on the tested paths, but radix-prefixed input returns wrong data with a 200 (W4). |
| simplicity | 9 | The smallest shape that meets the request. |
| test coverage | 6 | The list record shape is unpinned (W5) and the ordering tiebreaker cannot fail (W6). |
| clarity | 9 | Linear and readable; the envelope reads at a glance. |
| performance | 6 | Two queries per page, unindexed sort, and `SELECT *` pulling `description` for every row (W7). |
| security | 5 | No auth, no tenancy, no throttle on an endpoint built for external clients (W1). |

## 4. PLAN DRIFT

No material drift. Param parsing, the `offset < total` short-circuit, the float `ceil`, `rescue_from`, the
constants and the `ponytail:` comment all match the Design section. All 8 planned tests are present with
the planned inputs. Only `config/routes.rb`, `app/controllers/api/v1/` and `test/controllers/api/v1/`
changed.
