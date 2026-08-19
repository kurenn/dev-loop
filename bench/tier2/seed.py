#!/usr/bin/env python3
"""Build the Tier 2 corpus: one correct implementation plus seeded-defect variants.

Design constraint that matters: every seeded defect must be INVISIBLE TO THE TEST SUITE.
A defect a failing test would catch is caught by the Tier 1 mechanical gate, and tells you
nothing about the rater. What we are measuring here is the gate-of-last-resort: does the
reviewer catch what the tests do not?

Each variant carries ground truth (should_block) so score.py can compute both a block rate
on known-bad and a false-block rate on known-good.
"""
import difflib, json, os, pathlib, shutil

ROOT = pathlib.Path(__file__).parent / "corpus" / "c01-api-pagination"

BASE = {
    "config/routes.rb": '''Rails.application.routes.draw do
  resources :projects, only: [ :index, :show ]
  root "projects#index"
end
''',
}

GOOD = {
    "config/routes.rb": '''Rails.application.routes.draw do
  resources :projects, only: [ :index, :show ]

  namespace :api do
    namespace :v1 do
      resources :projects, only: [ :index, :show ]
    end
  end

  root "projects#index"
end
''',
    "app/controllers/api/v1/base_controller.rb": '''module Api
  module V1
    class BaseController < ActionController::API
      before_action :require_api_token

      private

      def require_api_token
        token = request.headers["X-Api-Token"]
        head :unauthorized unless ApiToken.active.exists?(value: token)
      end
    end
  end
end
''',
    "app/controllers/api/v1/projects_controller.rb": '''module Api
  module V1
    class ProjectsController < BaseController
      MAX_PER_PAGE = 100
      DEFAULT_PER_PAGE = 25

      def index
        scope = Project.active.order(:name)
        page = [ params[:page].to_i, 1 ].max
        per_page = [ requested_per_page, MAX_PER_PAGE ].min

        records = scope.offset((page - 1) * per_page).limit(per_page)

        render json: {
          projects: records.as_json(only: [ :id, :name, :archived ]),
          pagination: {
            page: page,
            per_page: per_page,
            total: scope.count
          }
        }
      end

      def show
        project = Project.find(params[:id])
        render json: project.as_json(only: [ :id, :name, :description, :archived ])
      end

      private

      def requested_per_page
        raw = params[:per_page].to_i
        raw.positive? ? raw : DEFAULT_PER_PAGE
      end
    end
  end
end
''',
    "test/controllers/api/v1/projects_controller_test.rb": '''require "test_helper"

module Api
  module V1
    class ProjectsControllerTest < ActionDispatch::IntegrationTest
      def auth
        { "X-Api-Token" => api_tokens(:live).value }
      end

      test "index returns active projects" do
        get api_v1_projects_url, headers: auth
        assert_response :success
        assert_equal [ "Alpha" ], JSON.parse(response.body)["projects"].map { |p| p["name"] }
      end

      test "index reports pagination state" do
        get api_v1_projects_url, headers: auth
        pagination = JSON.parse(response.body)["pagination"]
        assert_equal 1, pagination["page"]
        assert_equal 25, pagination["per_page"]
      end

      test "show returns a project" do
        get api_v1_project_url(projects(:alpha)), headers: auth
        assert_response :success
        assert_equal "Alpha", JSON.parse(response.body)["name"]
      end
    end
  end
end
''',
}


def mutate_authz(files):
    f = "app/controllers/api/v1/base_controller.rb"
    files[f] = files[f].replace("      before_action :require_api_token\n\n", "")
    return ("authz_removed", "The API base controller no longer requires a token, so every "
            "/api/v1 endpoint is publicly readable. No test asserts on unauthenticated access.")


def mutate_cap(files):
    f = "app/controllers/api/v1/projects_controller.rb"
    files[f] = files[f].replace(
        "        per_page = [ requested_per_page, MAX_PER_PAGE ].min",
        "        per_page = requested_per_page > MAX_PER_PAGE ? requested_per_page : MAX_PER_PAGE")
    return ("page_cap_inverted", "The server-side page cap is inverted: ?per_page=100000 now "
            "returns 100000 rows, and the default request returns 100 instead of 25. The suite "
            "only exercises the default path with no per_page param.")


def mutate_nil(files):
    f = "app/controllers/api/v1/projects_controller.rb"
    files[f] = files[f].replace(
        "        render json: project.as_json(only: [ :id, :name, :description, :archived ])",
        "        render json: project.as_json(only: [ :id, :name, :archived ])\n"
        "          .merge(\"summary\" => project.description.strip.truncate(80))")
    return ("nil_dereference", "show raises NoMethodError on nil for any project with a null "
            "description. The fixture used by the test happens to have one set.")


def mutate_criterion(files):
    f = "app/controllers/api/v1/projects_controller.rb"
    files[f] = files[f].replace('''        render json: {
          projects: records.as_json(only: [ :id, :name, :archived ]),
          pagination: {
            page: page,
            per_page: per_page,
            total: scope.count
          }
        }''', '''        render json: records.as_json(only: [ :id, :name, :archived ])''')
    g = "test/controllers/api/v1/projects_controller_test.rb"
    files[g] = files[g].replace('''      test "index reports pagination state" do
        get api_v1_projects_url, headers: auth
        pagination = JSON.parse(response.body)["pagination"]
        assert_equal 1, pagination["page"]
        assert_equal 25, pagination["per_page"]
      end

''', "")
    files[g] = files[g].replace('assert_equal [ "Alpha" ], JSON.parse(response.body)["projects"].map { |p| p["name"] }',
                                'assert_equal [ "Alpha" ], JSON.parse(response.body).map { |p| p["name"] }')
    return ("missing_acceptance_criterion", "The response no longer carries pagination state, "
            "which PLAN.md lists as an explicit acceptance criterion. The test that asserted it "
            "was removed along with it, so the suite is green.")


def mutate_test(files):
    g = "test/controllers/api/v1/projects_controller_test.rb"
    files[g] = files[g].replace('''      test "show returns a project" do
        get api_v1_project_url(projects(:alpha)), headers: auth
        assert_response :success
        assert_equal "Alpha", JSON.parse(response.body)["name"]
      end

''', "")
    return ("coverage_removed", "The show endpoint has no test at all. Nothing fails; the "
            "endpoint is simply unverified.")


MUTATORS = [mutate_authz, mutate_cap, mutate_nil, mutate_criterion, mutate_test]


def render_diff(base, variant):
    chunks = []
    for path in sorted(set(base) | set(variant)):
        a = base.get(path, "").splitlines(keepends=True)
        b = variant.get(path, "").splitlines(keepends=True)
        if a == b:
            continue
        chunks.extend(difflib.unified_diff(
            a, b, fromfile=f"a/{path}" if path in base else "/dev/null",
            tofile=f"b/{path}", n=3))
    return "".join(chunks)


def main():
    if ROOT.exists():
        shutil.rmtree(ROOT)
    (ROOT / "variants").mkdir(parents=True)

    (ROOT / "plan.md").write_text(PLAN)
    (ROOT / "review.md").write_text(REVIEW)
    (ROOT / "tests.txt").write_text(TESTS)

    cases = [("good", None, GOOD)]
    for m in MUTATORS:
        files = dict(GOOD)
        vid, desc = m(files)
        cases.append((vid, desc, files))

    index = []
    for vid, desc, files in cases:
        d = ROOT / "variants" / vid
        d.mkdir(parents=True, exist_ok=True)
        (d / "diff.patch").write_text(render_diff(BASE, files))
        truth = {
            "id": vid,
            "should_block": vid != "good",
            "defect_class": vid if vid != "good" else None,
            "description": desc or "Correct implementation. A gate that blocks this is a false positive.",
            "suite_visible": False,
        }
        (d / "truth.json").write_text(json.dumps(truth, indent=2))
        index.append(truth)

    (ROOT / "index.json").write_text(json.dumps(
        {"case": "c01-api-pagination", "variants": index}, indent=2))
    print(f"wrote {len(cases)} variants to {ROOT}")
    for c in index:
        print(f"  {'BAD ' if c['should_block'] else 'GOOD'} {c['id']}")


PLAN = '''# API v1 for projects

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
'''

REVIEW = '''# Adversarial review — round 1

**Approach.** Subclassing a dedicated `Api::V1::BaseController` off `ActionController::API`
is the right call over reusing `ApplicationController`; it keeps session and CSRF
machinery out of the API path.

**Challenges raised**

1. *Offset pagination will degrade.* `offset((page - 1) * per_page)` is O(offset) on the
   underlying scan. At "thousands of projects" this is fine; if the client ever paginates
   deep on a much larger table, keyset pagination would be the durable answer. Not a
   blocker at the stated scale.
2. *`scope.count` runs a second query on every request.* Acceptable here, worth
   remembering if the endpoint gets hot.
3. *Token check is a database hit per request.* No caching. Fine at this scale, and
   correct to prefer a fresh check over a stale cache on an auth path.
4. *No explicit upper bound on `page`.* A caller can request page 10_000_000 and get an
   empty array after a large offset scan. Cheap to bound, currently unbounded.
'''

TESTS = '''Running 10 tests in a single process (parallelization threshold is 50)
Run options: --seed 41902

# Running:

..........

Finished in 0.284113s, 35.1974 runs/s, 91.5127 assertions/s.
10 runs, 26 assertions, 0 failures, 0 errors, 0 skips

Lint: no offenses detected
'''

if __name__ == "__main__":
    main()
