# PLAN — versioned JSON API for projects (`/api/v1`)

## Problem
Mobile clients need a browser-independent JSON API for projects. `ProjectsController` inherits
`ActionController::Base` (browser stack: CSRF, cookies, `allow_browser`, importmap ETag — none of it wanted
by a JSON client), and its index dumps every active project as a bare array. Add `/api/v1/projects` (paginated,
server-capped page size, pagination metadata) and `/api/v1/projects/:id`; leave `/projects` untouched.

## Acceptance criteria
- [ ] AC1 `GET /api/v1/projects` → 200 `application/json`, body `{"data":[{id,name,archived}…],"pagination":{page,per_page,total_count,total_pages}}`; only `Project.active`; ordered `name ASC, id ASC`.
- [ ] AC2 `per_page` defaults to 25 and is capped at 100 (`per_page=1000` → 100 rows, `pagination.per_page == 100`).
- [ ] AC3 Missing / non-numeric / zero / negative / array-shaped `page` or `per_page` fall back to 1 / 25 — never 4xx/5xx.
- [ ] AC4 Page past the end (incl. `page=99999999999999999999`) → 200, `data: []`, metadata still accurate; no 500.
- [ ] AC5 Consecutive pages neither overlap nor skip (order `name ASC, id ASC`; pinned by the boundaries and tiebreaker tests).
- [ ] AC6 `GET /api/v1/projects/:id` → 200 `{id,name,description,archived}` for any project, archived included.
- [ ] AC7 Unknown id → 404 `application/json` body `{"error":"Not Found"}`.
- [ ] AC8 `Api::V1::ProjectsController` inherits `ActionController::API`, not `ApplicationController` (verified in the diff; no test).
- [ ] AC9 `/projects`, `/projects/:id`, `root` unchanged: `test/controllers/projects_controller_test.rb` byte-identical and green.
- [ ] AC10 Request tests for AC1–AC7 live in `test/controllers/api/v1/projects_controller_test.rb`; `bin/rails test` green; `Gemfile.lock` unchanged.

## Scope
In: `namespace :api { namespace :v1 { resources :projects, only: [:index, :show] } }`; one controller
`Api::V1::ProjectsController < ActionController::API`; one request-test file.
Out: auth/tenancy, CORS, filtering/sorting params, cursor pagination, next/prev links or `Link` headers,
ETags/caching, rate limiting, base controller / serializer / pagination concern, tasks in payload, OpenAPI
docs, any change to `ProjectsController`, `ApplicationController`, the model, or the schema.

## Risk tier
Light. No declared critical paths. Only shared file touched is `config/routes.rb` (additive nested block);
everything else is new files. No migrations, no writes, no model changes.

## Design (load-bearing details, so the implementer does not re-derive them)
- Params: `n = Integer(params[:x], exception: false)` (nil for garbage/arrays/nil — `.to_i` on an Array raises).
  `page = n&.positive? ? n : 1`; `per_page = n&.positive? ? [n, MAX_PER_PAGE].min : DEFAULT_PER_PAGE`.
- `total = Project.active.count`; `offset = (page - 1) * per_page`;
  rows = `offset < total ? scope.order(:name, :id).offset(offset).limit(per_page) : []`.
  The short-circuit is what makes AC4 hold: a bignum OFFSET cannot be bound as a 64-bit integer and raises
  (exact class unverified and irrelevant — the query is never issued).
- `total_pages = (total.to_f / per_page).ceil` (0 when empty). Metadata echoes the *effective* page/per_page.
- `rescue_from ActiveRecord::RecordNotFound { render json: { error: "Not Found" }, status: :not_found }`.
- Constants `DEFAULT_PER_PAGE = 25`, `MAX_PER_PAGE = 100` on the controller; tests hard-code 25/100.
- One `# ponytail:` comment on the offset line: offset pagination; switch to keyset if projects reach ~1M rows.

## Test strategy
Level: request tests only (`ActionDispatch::IntegrationTest`, matching the existing controller test).
Setup: `Project.insert_all` 101 rows `{ name: "P001".."P101", archived: false }` (column has no default; NULL is not `active`) (+ fixtures alpha/zulu → 102 active,
`"Alpha" < "P001" < "Zulu"` under SQLite BINARY collation). Transactional, rolled back per test.
- default list: 25 rows, first `Alpha`, pagination `{1, 25, 102, 5}` (`total_count` 102, not 103, is what proves archived Zulu is excluded), media type JSON. (AC1)
- cap: `per_page=10` → 10 rows, `per_page: 10`; `per_page=1000` → 100 rows, `per_page: 100`, `total_pages: 2`. (AC2)
- boundaries: `per_page=100` page 1 ends `P099`; page 2 == `[P100, P101]`; union of ids == all active ids, no dupes. (AC5)
- tiebreaker: 3 projects named `AAA`; `per_page=3` page 1 returns them in ascending id order (contract pin; keep compact). (AC5)
- garbage params: `page=abc&per_page=-5`, `per_page=0`, `page[]=1` → 200, page 1 / per_page 25. (AC3)
- past end: `page=999` and `page=99999999999999999999` → 200, `data: []`, `total_count: 102`. (AC4)
- show: zulu → 200, keys exactly `id name description archived`, `archived: true`. (AC6)
- 404: id 0 → 404, `response.media_type == "application/json"`, body `{"error"=>"Not Found"}`. (AC7)
Deliberately not tested: model, routing helpers in isolation, `.json` suffix, HTML/routing 404s for
unknown paths, performance. AC9 is pinned by leaving the existing test file untouched, not by new asserts.

## Assumptions (autonomous run — each ships unreviewed)
- A1 Auth: none. The app has no auth anywhere; the API is exactly as open as `/projects`. Must be revisited before public exposure.
- A2 Tenancy: none. No owner/account column exists; every caller sees every project.
- A3 Offset (`page`/`per_page`) not cursor pagination: "thousands" of rows on SQLite makes OFFSET cost negligible; cursor is more code and the request speaks in pages.
- A4 Default 25 / max 100: slow connection; 100 × ~60 B ≈ 6 KB per page is safe.
- A5 Invalid params clamp/default rather than 400: friendlier for a mobile client and no error path to maintain.
- A6 List scope = `Project.active` (mirrors `/projects`); show = any project including archived (mirrors `/projects/:id`).
- A7 Exposed fields mirror `/projects` exactly (list: id, name, archived; show adds description). No timestamps, no tasks.
- A8 Envelope `data` + `pagination{page, per_page, total_count, total_pages}`; no next/prev links (derivable client-side).
- A9 Order `name ASC, id ASC`: `projects.name` has no unique constraint, so `id` is required for stable pages.
- A10 Page past the end → 200 with empty `data` (not 404); metadata echoes the requested page.
- A11 404 via `rescue_from` in the controller, not the exceptions app, so the body is JSON regardless of `Accept` header or `show_exceptions` setting.
- A12 Superclass `ActionController::API` directly; no `Api::V1::BaseController` (single controller). Drops CSRF, `allow_browser`, importmap ETag.
- A13 Module is `Api::V1` (Zeitwerk default inflection; no `API` acronym inflection added).
- A14 Always renders JSON regardless of `Accept`; no `defaults: { format: :json }` needed in routes.
- A15 Tests live in `test/controllers/api/v1/` to mirror the existing layout (Minitest "request test" == IntegrationTest); `test/integration/` stays empty.
- A16 `insert_all` sets timestamps automatically (Rails ≥ 7); no per-record `create!` loop needed.
- A17 CORS not needed: native mobile client, not a browser.

## Work breakdown
### Wave 1 — API namespace
- **1.1 api-v1-projects** · owns: `config/routes.rb`, `app/controllers/api/v1/`, `test/controllers/api/v1/` · does: add the `api/v1` routes, `Api::V1::ProjectsController` per the Design section, and the request tests listed in Test strategy.
  · done when: AC1–AC10 all hold; `bin/rails test` reports 0 failures/errors with ≥ 15 runs; `git diff --stat` shows only the three owned paths and no `Gemfile*` change.

## Verification
`bin/rails test` (whole suite, expect baseline 7 runs + new tests, all green) and
`git status --porcelain` limited to `config/routes.rb`, `app/controllers/api/v1/`, `test/controllers/api/v1/`.

## Critique resolution (Phase 3)
- C1 accepted: AC8 is now a diff-verified superclass check; old-UA test, `/projects` 406 control and A18 removed.
- C2 rebutted: tiebreaker test kept (compacted to one `per_page=3` request). It asserts the ordering contract the client relies on; SQLite scan order may make it non-discriminating today, but it fails on any engine/index change that breaks id order, and dropping a tiebreaker pin is the known coverage-loss pattern.
- C3 accepted: `total_count` named as the archived-exclusion proof; `per_page=10` added to the cap test.
- C4 accepted: `archived: false` explicit in `insert_all`.
- C5 accepted: unverified exception class removed.
- C6 accepted: run floor → ≥ 15 (7 baseline + 8 new).
