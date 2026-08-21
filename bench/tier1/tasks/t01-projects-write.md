Projects are read-only right now — the index and show endpoints work, but there is no way
to create, update or archive one. Add write support to the projects resource: creating a
project, editing it, and archiving it (we archive rather than delete; a project that is
archived should drop off the index but still be reachable by id). Validation errors should
come back as JSON with a 422 rather than blowing up. Cover the new behaviour with tests.
