# Google Search Console API — manual setup

Use this when **`gcloud`** or Search Console API access fails during the seo-analysis preflight.

1. **Google Cloud project** — enable the [Search Console API](https://console.cloud.google.com/apis/library/searchconsole.googleapis.com).
2. **OAuth / Application Default Credentials** — run:
   `gcloud auth application-default login --scopes=https://www.googleapis.com/auth/webmasters,https://www.googleapis.com/auth/webmasters.readonly`
3. **Search Console access** — the Google account must be a verified owner or full user on the property you query.
4. **Quota project** — if you see quota errors:  
   `gcloud auth application-default set-quota-project "$(gcloud config get-value project)"`

Official reference: [Search Console API](https://developers.google.com/webmaster-tools/search-console-api-original).
