# Business context (project stub)

The full **seo-analysis** flow loads cached business context from **`~/.toprank/business-context/`** and sets **`CACHE_STATUS`**: `fresh_loaded`, `stale`, or `not_found`.

This repository does not ship the upstream generator. Until it is configured:

1. Treat **`CACHE_STATUS=not_found`** unless you have a real cache file.
2. In **Phase 2**, ask the user for comma-separated **brand terms** when the skill requires them; leave empty if they skip.
3. After the first successful upstream run, the cache JSON should include fields such as **`brand_terms`** for branded vs non-branded splits in GSC.

Replace this file with the real `business-context.md` from your TopRank-style package when available.
