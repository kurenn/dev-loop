# Shipped-defect probes for t04-api-v1. No flow ever saw these.
#
# These are NOT acceptance tests. bench/tier3/hidden asks "does it do what was asked"; this
# asks "did a known defect class reach main". Every probe here corresponds to something a
# rater actually found in bench/results/v03 — none is invented — and each one shipped in at
# least one run, which is the point: the loop's own gate let it past.
#
# A FAILING probe means THE DEFECT IS PRESENT. Read the output inverted.
#
# Shape tolerance is inherited from the hidden suite: arms return {data:,pagination:} or
# {projects:,pagination:} and grading one shape over the other would grade conformity to
# whichever implementation we happened to read first.
#
# SEVERITY is declared per probe and is deliberately conservative. The first writeup of
# this benchmark called D1 a "CPU denial-of-service" on the strength of a measurement that
# needed a 100,000-digit parameter no web server accepts; at lengths that actually arrive it
# costs 0.76 ms. Recording severity next to the probe is how that inflation gets caught by
# the harness instead of by a later reread.
require "test_helper"

class T04DefectProbe < ActionDispatch::IntegrationTest
  # probe id => [severity, what it is, which run shipped it]
  SEVERITY = {
    "D1" => ["minor", "unbounded page echoed back verbatim", "v0.2.6 #1/#2, v0.3 #1"],
    "D2" => ["major", "hostile page value reaches the query and 5xxs", "v0.3 #2 round 1"],
    "D3" => ["minor", "radix-prefixed params silently misread", "v0.2.6 #2"],
    "D5" => ["minor", "row timestamps leak into the list payload", "none observed"],
    "D6" => ["major", "negative per_page yields an empty page", "none observed"]
  }.freeze

  HOSTILE_PAGE = "9" * 25

  def json
    JSON.parse(response.body)
  rescue JSON::ParserError
    {}
  end

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

  def page_value(pg)
    return nil unless pg
    k = pg.keys.find { |x| x.to_s.downcase == "page" || x.to_s.downcase == "current_page" }
    k && pg[k]
  end

  def seed(n)
    n.times { |i| Project.create!(name: format("Probe %04d", i), archived: false) }
  end

  # D1 — the echoed page is whatever the client sent, with no upper bound. A client that
  # decodes pagination.page as a 64-bit integer fails to decode the whole response. Only a
  # caller that sent the bignum can trigger it, so this is minor and was graded MINOR by
  # every rater that saw it. It shipped in three of six t04 runs.
  test "D1 page echo is bounded" do
    get "/api/v1/projects", params: { page: HOSTILE_PAGE }
    echoed = page_value(pagination_in(json))
    skip "no pagination state to inspect" if echoed.nil?
    assert echoed.to_i <= 2**63 - 1,
           "DEFECT D1: echoed page is #{echoed.to_s[0, 30]}… — unbounded client input reflected"
  end

  # D2 — the hostile page reaches the database as an OFFSET it cannot bind, and the request
  # 500s. This is the genuine crash: v0.3 #2's round-1 code omitted the guard and returned
  # SQLite3::MismatchException. Major, and the loop caught it in that run.
  test "D2 hostile page does not 5xx" do
    get "/api/v1/projects", params: { page: HOSTILE_PAGE }
    assert response.status < 500,
           "DEFECT D2: page=#{HOSTILE_PAGE[0, 12]}… returned #{response.status}"
  end

  # D3 — Integer() honours radix prefixes, so per_page=010 is read as octal 8. Not a
  # fallback: a wrong answer served with a 200 and correct-looking metadata. Minor because
  # a client that serialises integers never emits it.
  test "D3 zero-padded per_page is not read as octal" do
    seed(60)
    get "/api/v1/projects", params: { per_page: "010" }
    n = (records_in(json) || []).size
    assert_not_equal 8, n,
                     "DEFECT D3: per_page=010 returned #{n} records — parsed as octal 8"
  end

  # D5 — list rows carry created_at/updated_at. Unlike `description`, which an arm might
  # expose deliberately, timestamps in a list payload are never asked for and are pure
  # weight on the connection the page size was sized for.
  test "D5 list rows do not leak timestamps" do
    get "/api/v1/projects"
    row = (records_in(json) || []).first
    skip "no records to inspect" if row.nil?
    leaked = row.keys.map(&:to_s) & %w[created_at updated_at]
    assert_empty leaked, "DEFECT D5: list rows expose #{leaked.join(', ')}"
  end

  # D6 — a negative or zero per_page falls through to a limit of 0 rather than the default,
  # so the endpoint returns an empty page for input the task says must fall back. Major:
  # silently empty results are the kind of thing a mobile client renders as "no projects".
  test "D6 negative per_page falls back rather than emptying the page" do
    seed(30)
    get "/api/v1/projects", params: { per_page: "-5" }
    n = (records_in(json) || []).size
    assert n.positive?, "DEFECT D6: per_page=-5 returned an empty page"
  end
end
