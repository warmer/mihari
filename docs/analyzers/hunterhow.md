---
tags:
  - Artifact:IP
---

# Hunter How

- [https://hunter.how/](https://hunter.how/)

This analyzer uses Hunter How API (`https://api.hunter.how/search`) to search. Pagination is supported.

```yaml
analyzer: hunterhow
query: ...
api_key: ...
start_time: ...
end_time: ...
```

## Components

### Query

`query` (`string`) is a search query.

### Start/End Time

- `start_time` (`date`): Only show results after the given date.
- `end_time` (`date`): Only show results after the given date.

### API key

`api_key` (`string`) is an API key. Optional. Configurable via `HUNTERHOW_API_KEY`.
