# Free location autocomplete deployment

Prepared for new free accounts; not deployed. The Godot app contains no Geoapify key. Its existing validated remote map configuration can enable this provider without changing the search code.

Geoapify's free plan permits commercial production use with attribution: 3,000 credits/day, up to 5 requests/sec; autocomplete costs one credit/request. First paid tier is $59/month; no paid enrollment is part of this setup. Cloudflare Workers Free and SQLite Durable Objects Free each include 100,000 requests/day; free limits stop operations rather than adding usage charges. Recheck dashboard plan selection at deployment. [Geoapify pricing](https://www.geoapify.com/pricing/), [autocomplete costs](https://www.geoapify.com/address-autocomplete/), [Workers](https://developers.cloudflare.com/workers/platform/pricing/), [Durable Objects](https://developers.cloudflare.com/durable-objects/platform/pricing/).

## API contract

- `GET /map-config.json`: schema-1 compatible provider configuration; search remains disabled without the server secret. No secrets in this response. Native clients refresh at most hourly.
- `GET /v1/places?q=Las%20Vegas&lang=en`: public read-only, HTTPS, 3–200 character query, optional language code; top **five** GeoJSON Point suggestions with `properties.formatted`. This is a finite autocomplete result, not a pageable data collection. No arbitrary URL, API-key, limit, identity or forwarding-header input.
- JSON errors have `{error:{code,message}}`. 400 invalid query; 405 method; 404 unknown path; 429 `rate_limit` or `daily_limit` with Retry-After; 503 service/provider failure. No upstream body or credential is echoed. GET can be retried safely, though each uncached upstream attempt conservatively uses one credit reservation.
- All uncached lookups go through the same Durable Object (`sincity-global-v1`). Its transactional persisted counter caps starts at 2,500 per rolling 24-hour window by default and four/second across all app users. The configurable cap is clamped to 3,000. Whole-hour buckets conservatively retain the oldest hour, so a full allowance may take up to 25 hours to recover; midnight cannot double it. Do not use this Geoapify account's remaining credits in other projects without adjusting the cap.
- Concurrent identical queries coalesce. At most 128 suggestion sets remain in memory, expiring after 15 minutes; a Durable Object alarm purges expired memory entries. Only aggregate usage counts/timestamps are persisted. Responses use `Cache-Control: no-store`; incoming IP, cookies, user agent and identity headers are not forwarded to Geoapify. No code request logs or Worker observability logs are enabled.
- This public endpoint can be discovered and its free quota exhausted by others. The hard cap protects the provider quota; it does not promise unlimited availability. Users retain map/coordinate selection. Stay on the free Cloudflare plan; an account upgrade changes the billing rules.

## Setup after free account registration

1. Create a Geoapify MyProjects account, select **Free**, create a project for SinCity, and obtain its API key. Do not paste the key into chat, a URL in public configuration, a source file, or a screenshot. Review its attribution and data-processing terms.
2. Create a Cloudflare account and select **Workers Free**. No custom domain is required; the resulting workers.dev URL is usable. The `new_sqlite_classes` migration uses the free-compatible storage backend.
3. In this folder, use the tested Wrangler 4.151.0 (`npx wrangler@4.151.0`). Authenticate with `wrangler login`. Store the key through the interactive secret command `wrangler secret put GEOAPIFY_API_KEY`; it is not a `[vars]` setting. Create the Worker on first deployment if prompted. Account authentication/terms need the account owner.
4. `wrangler deploy` only after the server files and account choices have been reviewed. Record the **actual** deployed HTTPS URL. Leave the daily cap at 2,500 initially; no paid subscription or auto-upgrade.
5. Fetch `/map-config.json`, confirm key-free output, run a real three-letter lookup and select a returned coordinate in the app. Test rate-limited and unavailable behavior. Confirm privacy/provider attribution on a signed device.
6. Point ProjectSettings `sincity/map/config_url` at that actual `/map-config.json` URL. The old `sincity-maps.sierraburkhart.com` host currently does not resolve from the development machine. Do not ship a guessed workers.dev URL or an unconfigured provider.
7. Finalize the offline/hosted privacy policy and Apple disclosures **before enabling** the provider in a submitted build. Keep Geoapify's clickable attribution and OSM credit visible. [API documentation](https://apidocs.geoapify.com/docs/geocoding/address-autocomplete/).

## Privacy delta

Autocomplete sends partial text as the user pauses typing, not just final submitted names. Cloudflare receives the network request/IP. The proxy keeps suggestion results/normalized queries in bounded memory for up to 15 minutes while active; only aggregate counters survive eviction. Geoapify receives the query and the proxy's outbound IP. Its policy states successful request information is generally retained for no longer than 24 hours for usage statistics, access control and API improvements. Cloudflare account/platform security-log retention still requires confirmation. Do not promise “Data Not Collected” or zero third-party retention. [Geoapify privacy](https://www.geoapify.com/privacy-policy/).

## Local verification

`node --test worker.test.mjs` runs offline provider mocks, concurrent shared-quota tests, cache/coalescing/expiry, rolling-window reset, validation and secret redaction. Wrangler dry-run verifies local bundling; it does not establish deployment or remote SQLite/account correctness. No real provider query is made without the owner's key.
