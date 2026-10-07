# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Named constants for the population system: census, demographics,
## settlement classes and the March vote.
class_name PopulationParams
extends RefCounted

# ── Census ───────────────────────────────────────────────────────────────

## Residents (or jobs) a developed lot holds, by footprint edge, when no zone
## system supplies a figure. Index 0 is unused.
const LOT_CAPACITY: Array[int] = [0, 10, 80, 360]
## The taller half of the 2×2 roster holds more people than the shorter half.
const LOT_CAPACITY_TALL_2X2 := 120
## Residents per census unit used by the unemployment ratio.
const CENSUS_UNIT := 10

# ── Service capacity ─────────────────────────────────────────────────────

## Pupils one fully funded school educates per aging step.
const SCHOOL_PLACES := 15
## Students one fully funded college serves per aging step.
const COLLEGE_PLACES := 50
## Patients one fully funded hospital cares for per month.
const HOSPITAL_PLACES := 25
## Adults one library or museum enriches per aging step.
const LIBRARY_PLACES := 40
const MUSEUM_PLACES := 25
## Residents per extra hospital place granted by the free-clinics ordinance.
const FREE_CLINIC_DIVISOR := 400

# ── Education ────────────────────────────────────────────────────────────

## Education gained by a schooled pupil at each aging step.
const SCHOOL_EQ_GAIN := 35
## Education gained by an adult mover with library or museum access.
const CULTURE_EQ_GAIN := 2
## Education forgotten at each aging step without the reading campaign.
const EQ_DECAY := 1
## Last cohort index (ages 10–14) that counts as school age.
const SCHOOL_COHORT_MAX := 2
## Cohorts (ages 15–24) that colleges serve.
const COLLEGE_COHORT_MIN := 3
const COLLEGE_COHORT_MAX := 4

# ── Health ───────────────────────────────────────────────────────────────

## Months over which a cohort with no health at all would die out.
const MORTALITY_MONTHS := 24
## Percent of deaths prevented when every resident has hospital care.
const HOSPITAL_MORTALITY_RELIEF := 25
## Health of a baby born with and without hospital care.
const NEWBORN_HEALTH_SERVED := 85
const NEWBORN_HEALTH_UNSERVED := 35
## Newborn health added by each health ordinance.
const HEALTH_ORDINANCE_BONUS := 5
## Newborn education as a fraction of the city's education quotient.
const NEWBORN_EQ_DIVISOR := 5
## Health lost at each aging step: average pollution divided by this, capped.
const POLLUTION_PENALTY_DIVISOR := 40
const POLLUTION_PENALTY_MAX := 3

# ── Births and migration ─────────────────────────────────────────────────

## Cohorts (ages 20–44) that have children; parents per birth per month.
const PARENT_COHORT_MIN := 4
const PARENT_COHORT_MAX := 8
const BIRTH_DIVISOR := 300
## Chance (out of BIRTH_DIVISOR) of the remainder birth lost per point of
## pollution penalty.
const BIRTH_POLLUTION_STEP := 25
## Cohorts immigrants fill, in order: young adults, children, then everyone
## of working age. Repeated until the newcomers are placed.
const IMMIGRATION_ORDER: Array[int] = [4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
## Immigrant health is this base minus the cohort index.
const IMMIGRANT_HEALTH_BASE := 65
## Child immigrants (cohorts 0–2) arrive with base + step × index education.
const IMMIGRANT_EQ_CHILD_BASE := 17
const IMMIGRANT_EQ_CHILD_STEP := 35
## Adult immigrants arrive with this base minus the cohort index.
const IMMIGRANT_EQ_ADULT_BASE := 90

# ── Headline scores ──────────────────────────────────────────────────────

## Working-age cohorts (ages 20–54) that define the headline averages.
const WORK_COHORT_MIN := 4
const WORK_COHORT_MAX := 10
## Ceilings for the headline scores.
const EQ_MAX := 150
const LE_MAX := 90
## Headline education bonus when libraries and museums cover every resident.
const CULTURE_EQ_BONUS := 10
## Headline life expectancy bonus when hospitals cover every resident.
const HOSPITAL_LE_BONUS := 10
## Life expectancy added by each health ordinance.
const LE_ORDINANCE_BONUS := 1

# ── Settlement class ─────────────────────────────────────────────────────

## Population above which each class ends; index 0 is the village floor.
const STATUS_THRESHOLDS: Array[int] = [0, 2000, 10000, 50000, 100000, 500000]
const STATUS_NAMES: Array[String] = [
	"Village", "Town", "City", "Capital", "Metropolis", "Megalopolis",
]

# ── March vote ───────────────────────────────────────────────────────────

## Residents needed before a vote is held.
const VOTE_MIN_POPULATION := 100
## Voters polled; approval is the number who approve.
const VOTE_COUNT := 100
## Complaint weight per point of residential tax.
const VOTE_TAX_WEIGHT := 3
## Life expectancy below which health becomes a complaint.
const VOTE_HEALTH_TARGET := 70
## Baseline contentment added to the average land value.
const VOTE_CONTENT_BASE := 50
## Approval that triggers the milestone notice.
const APPROVAL_MILESTONE := 80
## Complaint keys and labels, in weight order.
const COMPLAINT_KEYS: Array[StringName] = [
	&"traffic", &"pollution", &"crime", &"taxes", &"unemployment", &"education", &"health",
]
const COMPLAINT_NAMES: Array[String] = [
	"Traffic", "Pollution", "Crime", "Taxes", "Unemployment", "Education", "Health",
]

# ── News ─────────────────────────────────────────────────────────────────

## Births in one month before a record month is reported.
const NEWS_BIRTHS_MIN := 10

# ── Ordinance keys ───────────────────────────────────────────────────────

const ORDINANCE_PRO_READING := &"pro_reading_campaign"
const ORDINANCE_FREE_CLINICS := &"free_clinics"
const ORDINANCE_ANTI_DRUG := &"anti_drug_campaign"
const ORDINANCE_SMOKING_BAN := &"public_smoking_ban"


## Fallback capacity of a developed or abandoned lot by footprint. Abandoned
## lots report the capacity they had when occupied.
static func lot_capacity(id: int) -> int:
	var category := Buildings.category(id)
	var counted := Buildings.is_zone_building(id) or category == Buildings.Category.ABANDONED
	if not counted:
		return 0
	var edge := Buildings.size(id).x
	if edge < 1 or edge >= LOT_CAPACITY.size():
		return 0
	if edge == 2 and Buildings.is_zone_building(id) and _is_tall_2x2(id):
		return LOT_CAPACITY_TALL_2X2
	return LOT_CAPACITY[edge]


static func _is_tall_2x2(id: int) -> bool:
	var first := 0
	var last := 0
	match Buildings.category(id):
		Buildings.Category.RESIDENTIAL:
			first = Buildings.RES_2X2_FIRST
			last = Buildings.RES_2X2_LAST
		Buildings.Category.COMMERCIAL:
			first = Buildings.COM_2X2_FIRST
			last = Buildings.COM_2X2_LAST
		Buildings.Category.INDUSTRIAL:
			first = Buildings.IND_2X2_FIRST
			last = Buildings.IND_2X2_LAST
		_:
			return false
	return id - first >= (last - first + 1) / 2


static func status_name(status: int) -> String:
	return STATUS_NAMES[clampi(status, 0, STATUS_NAMES.size() - 1)]
