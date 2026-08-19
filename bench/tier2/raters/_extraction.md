
---
Finally, after your prose, emit one fenced json block, exactly:

```json
{"axes": {"<axis name>": <1-10>, ...},
 "overall": <1-10 or null if you were not asked for one>,
 "findings": [{"severity": "BLOCKING|MAJOR|MINOR", "summary": "<one line>"}]}
```

Include every axis you scored and every finding you raised. If your instructions did not
ask you for one of these fields, use null for it. Emit nothing after the block.
