# API v1 for projects

## Problem & acceptance criteria

A mobile client needs a versioned JSON API for projects that does not depend on the
existing HTML-era controller.

- [ ] `GET /api/v1/projects` returns active projects as JSON
- [ ] `GET /api/v1/projects/:id` returns a single project
- [ ] The list is paginated, and the page size is capped server-side so a caller cannot
      request an unbounded number of rows
- [ ] The list response carries the pagination state alongside the records
- [ ] Every `/api/v1` endpoint requires a valid API token
- [ ] The existing `/projects` endpoints keep working unchanged
- [ ] Request tests cover the new namespace

## Scope

In: a new `Api::V1` controller namespace, routes, request tests.
Out: write endpoints, rate limiting, the existing HTML controller.

## Risk tier

Touches a declared critical path: **auth**. Every endpoint in this namespace is
authenticated, and the page cap is the only thing bounding response size.

## Test strategy

Request tests at the integration level for both endpoints, the default pagination state,
and rejection of an unauthenticated request.

## Work breakdown

### Wave 1 — routing and base controller
- **1.1 API namespace** · owns: `config/routes.rb`,
  `app/controllers/api/v1/base_controller.rb` · does: adds the namespace and the shared
  token check · done when: an unauthenticated request to any `/api/v1` route gets a 401

### Wave 2 — resource and tests
- **2.1 Projects endpoints** · owns: `app/controllers/api/v1/projects_controller.rb`
  · does: index with capped pagination and pagination metadata, plus show
  · done when: every acceptance criterion above is met
- **2.2 Request tests** · owns: `test/controllers/api/v1/projects_controller_test.rb`
  · does: covers both endpoints, the pagination state and the auth rejection
  · done when: the suite is green and each criterion has a corresponding assertion
