
---
Finally, after your prose, emit one fenced json block, exactly:

```json
{"decisions": [{"id": "<finding id, e.g. W1>",
                "action": "fix|waive",
                "ground": "out_of_scope|pre_existing|approved_assumption|null",
                "reason": "<your one-line reason>"}]}
```

One entry per MAJOR finding in the rating, using the finding's own id. Use `null` for
`ground` on anything you chose to fix, and on any waiver where your instructions did not ask
you to name a ground. Emit nothing after the block.
