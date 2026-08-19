# Adversarial review — round 1

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
