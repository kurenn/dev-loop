# API v1 for projects

## Problem & acceptance criteria

A mobile client needs a versioned JSON API for projects that does not depend on the
existing HTML-era controller.

- [ ] `GET /api/v1/projects` returns active projects as JSON
- [ ] `GET /api/v1/projects/:id` returns a single project
- [ ] The list is paginated, and the page size is capped server-side so a caller cannot
      request an unbounded number of rows
- [ ] The list response carries the pagination state alongside the records
- [ ] Every `/api/v1` endpoint requires a valid, active API token; a missing or revoked
      token gets a 401
- [ ] Archived projects stay reachable by id even though the list hides them
- [ ] An unknown project id returns a JSON 404, not an HTML error page
- [ ] The existing `/projects` endpoints keep working unchanged
- [ ] Request tests cover the new namespace, including the auth rejections and the cap

## Scope

In: a new `Api::V1` controller namespace, routes, request tests.
Out: write endpoints, rate limiting, the existing HTML controller.

## Risk tier

Touches a declared critical path: **auth**. Every endpoint in this namespace is
authenticated, and the page cap is the only thing bounding response size.

## Test strategy

Request tests at the integration level for both endpoints, the default pagination state,
the server-side page cap, the JSON 404, and rejection of both a missing and a revoked
token.

## Work breakdown

### Wave 1 — routing and base controller
- **1.1 API tokens** · owns: `app/models/api_token.rb`,
  `db/migrate/20260819000600_create_api_tokens.rb`, `test/fixtures/api_tokens.yml`
  · does: the token record the auth check reads, with a unique index on the value
  · done when: an active and a revoked token fixture both exist
- **1.2 API namespace** · owns: `config/routes.rb`,
  `app/controllers/api/v1/base_controller.rb` · does: adds the namespace and the shared
  token check · done when: an unauthenticated request to any `/api/v1` route gets a 401

### Wave 2 — resource and tests
- **2.1 Projects endpoints** · owns: `app/controllers/api/v1/projects_controller.rb`
  · does: index with capped pagination and pagination metadata, plus show
  · done when: every acceptance criterion above is met
- **2.2 Request tests** · owns: `test/controllers/api/v1/projects_controller_test.rb`
  · does: covers both endpoints, the pagination state and the auth rejection
  · done when: the suite is green and each criterion has a corresponding assertion
