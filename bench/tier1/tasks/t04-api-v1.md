Stand up a versioned JSON API for projects under /api/v1 so a mobile client can consume it
without depending on the current HTML-era controller. It needs a project list and a single
project endpoint. The list has to be paginated — the client will be on a slow connection
and we have customers with thousands of projects — with the page size capped server-side
so a caller can't ask for everything at once. Responses should carry the pagination state
alongside the records. Keep the existing /projects endpoints working unchanged, and write
request tests for the new namespace.
