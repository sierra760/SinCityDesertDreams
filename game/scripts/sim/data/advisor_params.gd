# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends RefCounted

## Advice policy, not simulation balance. Coverage 32 is below the fully
## funded outer ring (50); warn when at least a fifth of occupied lots lack it.
const COVERAGE_STRENGTH := 32
const COVERAGE_GAP_PERCENT := 20
const RESERVE_PERCENT := 2
const POOR_HEALTH := 50
const POOR_EDUCATION := 80
const ROUTE_FAILURE_PERCENT := 20
const TAX_WARNING := 12
const VISITOR_TAX_WARNING := 12
const GROWTH_CAP_PERCENT := 90
const EMERGENCY := 1000
const ESSENTIAL := 900
const SERIOUS := 700
const WARNING := 500
const OPPORTUNITY := 100
