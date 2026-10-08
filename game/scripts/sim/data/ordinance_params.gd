# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Named constants for the ordinance system. See docs/simulation/ordinances.md.
class_name OrdinanceParams
extends RefCounted

const GROUP_FINANCE := &"finance"
const GROUP_SAFETY := &"safety"
const GROUP_CITY := &"city"

## Residents each yearly rate is quoted against.
const PER_CAPITA_UNIT := 10000

## The catalog, in display order: key, group, name, description.
const CATALOG: Array[Array] = [
	[&"sales_tax", GROUP_FINANCE, "Sales Tax", "A small levy on every purchase in town. Shops feel it as a higher tax rate."],
	[&"income_tax", GROUP_FINANCE, "Income Tax", "A levy on residents' earnings. Households feel it as a higher tax rate."],
	[&"parking_fines", GROUP_FINANCE, "Parking Fines", "Meter patrols ticket the downtown curbs. Steady money, mild grumbling."],
	[&"legalized_gambling", GROUP_FINANCE, "Legalized Gambling", "Licensed card rooms and slot halls pay the city a share, and bring some crime with them."],
	[&"tourist_advertising", GROUP_FINANCE, "Tourist Advertising", "Billboards on the interstate invite visitors. Shops enjoy a lower effective tax."],
	[&"business_advertising", GROUP_FINANCE, "Business Advertising", "Trade-journal campaigns court factories. Industry enjoys a lower effective tax."],
	[&"volunteer_fire", GROUP_SAFETY, "Volunteer Fire Department", "Trained neighbors back up the fire stations, widening coverage for a modest stipend."],
	[&"public_smoking_ban", GROUP_SAFETY, "Public Smoking Ban", "No smoking indoors in public places. Cheap to enforce and good for health."],
	[&"free_clinics", GROUP_SAFETY, "Free Clinics", "Walk-in clinics for anyone. Costly, and it lengthens lives."],
	[&"junior_sports", GROUP_SAFETY, "Junior Sports", "Little leagues and after-school teams keep kids busy and learning."],
	[&"anti_drug_campaign", GROUP_SAFETY, "Anti-Drug Campaign", "Outreach and counseling. Improves health and trims crime."],
	[&"neighborhood_watch", GROUP_SAFETY, "Neighborhood Watch", "Residents keep an eye on each block. Crime falls where people look out for each other."],
	[&"cpr_training", GROUP_SAFETY, "CPR Training", "Free first-aid courses. A few more emergencies end well."],
	[&"pollution_controls", GROUP_CITY, "Pollution Controls", "Scrubbers and inspections for industry. Cleaner air, higher effective industrial tax."],
	[&"energy_conservation", GROUP_CITY, "Energy Conservation", "Insulation grants and efficient fixtures stretch the power supply. Everyone pays a little."],
	[&"nuclear_free_zone", GROUP_CITY, "Nuclear Free Zone", "No nuclear plants may be built inside city limits. Costs nothing."],
	[&"homeless_shelters", GROUP_CITY, "Homeless Shelters", "Beds and meals for those without. Costly, but the city feels kinder and shops do better."],
	[&"pro_reading_campaign", GROUP_CITY, "Pro-Reading Campaign", "Library drives and literacy tutors. Education rises a little every year."],
	[&"tree_planting", GROUP_CITY, "Tree Planting", "Shade trees along every street. Cleaner air, and households enjoy a lower effective tax."],
	[&"annual_carnival", GROUP_CITY, "Annual Carnival", "A week of rides and fireworks each spring. Shops enjoy a lower effective tax."],
]

## Yearly dollars per PER_CAPITA_UNIT residents; positive is income.
const YEARLY_RATE := {
	&"sales_tax": 40,
	&"income_tax": 133,
	&"parking_fines": 67,
	&"legalized_gambling": 80,
	&"tourist_advertising": -40,
	&"business_advertising": -40,
	&"volunteer_fire": -44,
	&"public_smoking_ban": -7,
	&"free_clinics": -67,
	&"junior_sports": -33,
	&"anti_drug_campaign": -27,
	&"neighborhood_watch": -44,
	&"cpr_training": -22,
	&"pollution_controls": -40,
	&"energy_conservation": -133,
	&"nuclear_free_zone": 0,
	&"homeless_shelters": -67,
	&"pro_reading_campaign": -22,
	&"tree_planting": -33,
	&"annual_carnival": -7,
}

## One-point adjustments to the tax rates residents, shops and industry feel:
## key -> [res, com, ind]. Read by zone demand and the March vote through
## `OrdinanceSystem.effective_rates`; property tax keeps the player's rates.
const DEMAND_TAX_SHIFT := {
	&"income_tax": [1, 0, 0],
	&"tree_planting": [-1, 0, 0],
	&"sales_tax": [0, 1, 0],
	&"tourist_advertising": [0, -1, 0],
	&"annual_carnival": [0, -1, 0],
	&"homeless_shelters": [0, -1, 0],
	&"pollution_controls": [0, 0, 1],
	&"business_advertising": [0, 0, -1],
}

## The council acts on its own once in this many months, on average.
const COUNCIL_CHANCE_DENOMINATOR := 8
## The treasury must exceed this plus a random amount up to the spread.
const COUNCIL_RICH_FUNDS := 50000
const COUNCIL_RICH_SPREAD := 65536
