# Hidden acceptance tests for t04-api-v1. Neither flow ever saw these.
#
# Graded against the TASK TEXT, not against either implementation, so every assertion is
# tolerant of response shape: the task specified behaviour ("paginated", "capped
# server-side", "carry the pagination state alongside the records") and deliberately not a
# JSON schema. v0.1 returns {data:, pagination:}; v0.2.2 returns {projects:, pagination:}.
# Rewarding one shape over the other would be grading conformity to whichever we looked at
# first.
#
# Note on fixtures: the pristine app's `archived` column has no default, and Project.active
# is `where(archived: false)`, so rows created without an explicit archived value are
# invisible to it. Seeds below always set it.
require "test_helper"

class T04AcceptanceTest < ActionDispatch::IntegrationTest
  CAP_EXPECTED = 100

  def json
    JSON.parse(response.body)
  end

  # Find the first array of record-like hashes anywhere in the payload.
  def records_in(node)
    case node
    when Array
      return node if node.all? { |e| e.is_a?(Hash) && e.key?("id") && e.key?("name") }
      node.each { |e| found = records_in(e); return found if found }
      nil
    when Hash
      node.each_value { |v| found = records_in(v); return found if found }
      nil
    end
  end

  # Find a hash carrying pagination state under any key naming.
  def pagination_in(node)
    case node
    when Hash
      keys = node.keys.map(&:to_s).map(&:downcase)
      has_page = keys.any? { |k| k == "page" || k.end_with?("_page") || k == "current_page" }
      has_size = keys.any? { |k| k.include?("per_page") || k == "perpage" || k == "limit" || k == "page_size" }
      return node if has_page && has_size
      node.each_value { |v| found = pagination_in(v); return found if found }
      nil
    when Array
      node.each { |e| found = pagination_in(e); return found if found }
      nil
    end
  end

  def seed(n, archived: false)
    n.times { |i| Project.create!(name: format("Seed %04d", i), archived: archived) }
  end

  test "A1 list endpoint returns active projects as json" do
    get "/api/v1/projects"
    assert_response :success
    recs = records_in(json)
    assert recs, "no array of project records found in response: #{response.body[0, 200]}"
    assert recs.any?, "list came back empty"
  end

  test "A2 list excludes archived projects" do
    get "/api/v1/projects"
    names = (records_in(json) || []).map { |r| r["name"] }
    assert_not_includes names, "Zulu", "archived project leaked into the list"
  end

  test "A3 single project endpoint returns that project" do
    get "/api/v1/projects/#{projects(:alpha).id}"
    assert_response :success
    assert_equal "Alpha", json["name"] || json.dig("data", "name") || json.dig("project", "name")
  end

  test "A4 response carries pagination state alongside the records" do
    get "/api/v1/projects"
    pg = pagination_in(json)
    assert pg, "no pagination state found in response: #{response.body[0, 200]}"
  end

  test "A5 page size is capped server side" do
    seed(150)
    get "/api/v1/projects", params: { per_page: 100_000 }
    assert_response :success
    recs = records_in(json) || []
    assert recs.size <= CAP_EXPECTED,
           "per_page=100000 returned #{recs.size} records; server-side cap did not hold"
    assert recs.size < Project.active.count, "cap did not bound the result below the total"
  end

  test "A6 pagination actually pages" do
    seed(60)
    get "/api/v1/projects", params: { page: 1, per_page: 10 }
    first = (records_in(json) || []).map { |r| r["id"] }
    get "/api/v1/projects", params: { page: 2, per_page: 10 }
    second = (records_in(json) || []).map { |r| r["id"] }
    assert_equal 10, first.size, "page 1 did not honour per_page=10"
    assert first.any? && second.any?, "a page came back empty"
    assert_empty(first & second, "page 1 and page 2 overlap")
  end

  test "A7 existing projects endpoints still work unchanged" do
    get "/projects"
    assert_response :success
    body = JSON.parse(response.body)
    names = (body.is_a?(Array) ? body : records_in(body) || []).map { |r| r["name"] }
    assert_includes names, "Alpha", "legacy /projects endpoint regressed"
  end

  test "A8 malformed pagination params do not 500" do
    get "/api/v1/projects", params: { page: "abc", per_page: "-5" }
    assert response.status < 500, "malformed params returned #{response.status}"
  end
end
