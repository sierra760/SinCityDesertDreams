# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Named constants for the newspaper and advisor system.
class_name NewspaperParams
extends RefCounted

## Masthead printed on every issue.
const TITLE := "The Desert Dispatch"

## Pending stories kept between issues; the least important is squeezed out.
const QUEUE_SIZE := 9
## Reported stories printed per issue (the first is the lead).
const LEAD_COUNT := 3
## Total stories per issue; the rest are human-interest fillers.
const ISSUE_STORIES := 6
## Issues kept in the archive: five years of monthly papers plus extras.
const ARCHIVE_ISSUES := 60

## Story importance classes. A template names one of these.
const PRIORITY_MINOR := 200
const PRIORITY_NOTABLE := 360
const PRIORITY_MAJOR := 500
const PRIORITY_URGENT := 1000

## A story at or above this priority breaks an extra edition the day it lands.
const EXTRA_PRIORITY := PRIORITY_URGENT

## Monthly priority loss classes. SLOW stories linger for a few issues, FAST
## ones for one or two, ONCE stories are printed now or never.
const DECAY_SLOW := 50
const DECAY_FAST := 250
const DECAY_ONCE := 1000

## Advisor thresholds.
## Unused utility capacity (percent) below which a shortage is advised.
const SHORTAGE_MARGIN := 2
## Unemployment percent that draws an advisor warning.
const UNEMPLOYMENT_WARNING := 10
## Average pollution index that draws a warning.
const POLLUTION_WARNING := 100
## Average traffic index that draws a warning.
const TRAFFIC_WARNING := 100
## Average crime index that draws a call for police.
const CRIME_WARNING := 100
## Any tax rate at or above this percent draws a warning.
const TAX_WARNING := 12
## Approval below this percent draws a warning.
const APPROVAL_WARNING := 40
