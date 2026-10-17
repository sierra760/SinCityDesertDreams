# Privacy release preparation — October 14, 2026

The app has an offline Privacy window on the title screen, in Help, and in Playing the Game, including the unfounded-city stage. Every export carries `legal/PRIVACY.txt`. A verified HTTPS address in ProjectSettings `sincity/privacy/policy_url` enables Online Policy. Browser failure retains offline reading. The draft has no invented contact or retention statement.

The publisher answered “I don't know” when asked for support email, policy URL and map-host access logs. The draft **must not be submitted** until these fields are resolved. `app-store-draft/privacy.html` is a matching static publication preview, not a deployed site.

## Data inventory for publisher confirmation

| Flow | Sent off device | Known retention | Next action |
| --- | --- | --- | --- |
| Local gameplay/settings | Local files; cloud transfer applies separately when enabled | Local files; user-controlled OS backup | Explain local deletion and exported copies |
| Enabled iCloud Saves | Private CloudKit continuation/manual/conflict `.sc2d` assets; names, terrain/layout, custom text, simulation/financial history and mod progress; library header, app-specific installation/slot/revision IDs, hashes, conflict ancestry, coarse platform label, Apple record/change metadata | No automatic app expiry; disabling or local deletion does not erase prior cloud copies; Apple storage/account controls and retention apply | Verify provisioned build and Apple disclosures; do not assume private iCloud means no collection or end-to-end encryption |
| System share sheet | Selected city file, possibly mayor/city names and history | Destination-dependent | Explain deliberate sharing |
| Map configuration | IP, user agent, request path | Publisher host unknown; current DNS lookup failed | Identify actual hosting account, logging/CDN/security-log policy and retention |
| OSM map tiles | IP, user agent, selected tile coordinates | Provider policy | Confirm Apple data types/purposes from actual use and current policy |
| Terrarium/WorldCover S3 terrain | IP and selected tile coordinates | Provider policy | Confirm retention and downstream privacy disclosure |
| Prepared Geoapify autocomplete proxy | Partial text after a pause, language; Cloudflare receives client IP, Geoapify receives proxy IP | Proxy bounded 15-minute memory suggestions, aggregate counters persisted; Geoapify successful request information generally ≤24h | Free accounts/key/endpoint not configured; confirm Cloudflare platform retention and Apple disclosures before enabling |

Apple defines collection as off-device transmission plus retention beyond servicing a request. A local-only game loop does not establish “Data Not Collected” for the optional network services. IP classification depends on its actual purpose; selected terrain coordinates are not automatically a user's location. Do not infer a data category merely from URL shape. [Apple privacy details](https://developer.apple.com/app-store/app-privacy-details/).

## Concrete publication proposal

Use the verified public project repository for bug reports: `https://github.com/sierra760/SinCityDesertDreams/issues`. Verify that Issues is enabled and accessible before using it as support. A privacy contact still needs a monitored address or a suitable private contact channel; public bug reports should not request private data.

Publish the reviewed HTML on a publisher-controlled HTTPS site (GitHub Pages is an option once enabled). Do not invent the resulting URL or assume a repository grants Pages hosting. After publication: check HTTP 200 without login, responsive reading, functioning contact, a stable link; insert that exact URL in the app and App Store Connect. Remove the draft paragraphs in both offline text and HTML only after replacing the pending facts with verified ones.

No hosted files, account privacy declarations or legal agreements have been published or accepted by this task.

The implemented server is `services/place-search/`. It does not print request data, and its checked Wrangler configuration disables observability. Cloudflare platform security logs are distinct from application logging and still require account-side confirmation. Provider attribution has a 44-point clickable link in the terrain chooser. Source export collected-data flags have not been silently changed while this provider is unconfigured; activation must include the matching declaration/manifest review.

## iCloud save inventory and activation gate

`apple-cloud-saves.md` maps every CloudKit record field and the payload to the
implemented writer/transport. The offline text and HTML draft describe this
same optional, default-on-on-configured-build flow. The tracked unprovisioned
project remains disabled. No public database, publisher save server, Game Center,
tracking or analytics is introduced. The local account partition hash, paths,
journal and opaque sync tokens are not extra fields inside portable `.sc2d`
files. Apple-owned system record metadata is separate from application fields.

Finalize the applicable App Store privacy answers from the enabled shipping
build and current Apple guidance; this task does not silently change the
unresolved terrain/provider collected-data flags. Contact, hosted URL and
publisher/provider retention questions above remain pending. Do not claim
cloud records expire or that deleting a local file removes all cloud copies.
