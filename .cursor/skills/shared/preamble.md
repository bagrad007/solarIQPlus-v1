# SEO skill — preflight (project stub)

The **seo-analysis** skill expects TopRank-style automation: Python scripts on **`SKILL_SCRIPTS`**, caches under **`~/.toprank/`**, and **Google Search Console** access via **`gcloud auth application-default login`** with webmasters scopes.

## If you do not have those scripts yet

1. Install or vendor the plugin/package that provides `list_gsc_sites.py`, `analyze_gsc.py`, `show_gsc.py`, `url_inspection.py`, `pagespeed.py`, `show_pagespeed.py`, `cms_detect.py`, etc., and set **`SKILL_SCRIPTS`** to that directory (export in your shell or document it in `~/.toprank/.env`).
2. Without GSC: follow the skill’s **Phase 5** path (technical crawl, metadata, schema, PageSpeed where APIs allow) and state that automated GSC phases were skipped.
3. Optional: **`PAGESPEED_API_KEY`** in the environment for higher PageSpeed quota ([Google API credentials](https://console.cloud.google.com/apis/credentials)).

Replace this stub with your real preamble when you wire scripts, or symlink the upstream `preamble.md` here.
