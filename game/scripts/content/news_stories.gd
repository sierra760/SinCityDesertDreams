# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Story templates for The Desert Dispatch.
##
## Every kind the systems report has a template with several headline variants
## and a short body. Text uses the placeholders {city}, {mayor}, {year},
## {count}, {place} and {kind}; `fill` resolves them. Fillers are small pieces
## of local colour printed when the month is short on news.
class_name NewsStories
extends RefCounted

const MINOR := NewspaperParams.PRIORITY_MINOR
const NOTABLE := NewspaperParams.PRIORITY_NOTABLE
const MAJOR := NewspaperParams.PRIORITY_MAJOR
const URGENT := NewspaperParams.PRIORITY_URGENT
const SLOW := NewspaperParams.DECAY_SLOW
const FAST := NewspaperParams.DECAY_FAST
const ONCE := NewspaperParams.DECAY_ONCE

const GENERIC := &"generic"
const QUIET := &"quiet_month"

## kind -> {priority, decay, headlines: [String], body: [paragraph String]}
const STORIES: Dictionary = {
	&"generic": {
		"priority": MINOR, "decay": SLOW,
		"headlines": [
			"Something Happened In {city}, Sources Confirm",
			"{city} Notes A Development Near {place}",
			"Council Aware Of Matter Near {place}",
			"Word Travels Fast Along Main Street",
		],
		"body": [
			"Details were thin on the ground, which in {city} is saying something. What is known is that something took place near {place} and that people have opinions about it.",
			"The mayor's office said the matter was being looked into. The Dispatch will report further once someone tells us anything.",
		],
	},
	# Military base decisions keep the generic story's priority, decay and four
	# headlines, so the newspaper queue and headline draw are unchanged.
	&"military_base_accepted": {
		"priority": MINOR, "decay": SLOW,
		"headlines": [
			"Council Welcomes Military Base To {city}",
			"Base Deal Signed; Fences Go Up Outside {city}",
			"{city} Says Yes To The Military",
			"Uniforms Coming To {city} After Base Vote",
		],
		"body": [
			"The council approved a military base on the edge of {city} this month. Supporters point to steady paychecks; neighbors point to the noise.",
			"The base will sit on land set aside by the council and cannot be zoned for anything else.",
		],
	},
	&"military_base_declined": {
		"priority": MINOR, "decay": SLOW,
		"headlines": [
			"{city} Turns Down Military Base",
			"Council Says No Thanks To The Generals",
			"Base Proposal Shelved In {city}",
			"No Barracks For {city}, Council Decides",
		],
		"body": [
			"The council declined an offer to host a military base in {city} this month. The land stays open for whatever the city decides to build there.",
			"Officials said the offer will not be repeated.",
		],
	},
	&"quiet_month": {
		"priority": 0, "decay": ONCE,
		"headlines": [
			"Nothing Much Happened; Residents Relieved",
			"A Quiet Month In {city}",
			"Slow News Month Declared Official",
			"Wind Blows, Sun Sets, {city} Carries On",
			"Dispatch Editor Considers Fishing Trip",
		],
		"body": [
			"By every measure the Dispatch keeps, {year} in {city} continued at its usual pace this month. No sirens, no speeches, and the dust settled where it fell.",
			"Old-timers on the courthouse bench called it the best kind of news. The editor, who has a page to fill, disagreed but was outvoted.",
		],
	},
	&"power_shortage": {
		"priority": MAJOR, "decay": FAST,
		"headlines": [
			"Lights Flicker Across {city} As Plant Strains",
			"Brownout Leaves {count} Buildings In The Dark",
			"Power Falls Short; Fans Stop, Tempers Rise",
			"Grid Can't Keep Up With {city}",
			"Candles Sell Out At Every Store In Town",
		],
		"body": [
			"Generating capacity in {city} could not meet demand this month, and {count} buildings went dark. Refrigerators hummed to a stop and the neon along the strip went out one sign at a time.",
			"The utility board says the fix is more capacity or fewer customers, and nobody is volunteering to be a fewer customer. Mayor {mayor} has been urged to site a new plant before the summer heat.",
		],
	},
	&"plant_retired": {
		"priority": MAJOR, "decay": FAST,
		"headlines": [
			"Aging Power Plant At {place} Shuts Down For Good",
			"Plant Reaches End Of Its Working Life",
			"Fifty Years Of Sparks: Plant Near {place} Retires",
			"Old Generator Goes Quiet; Bills Expected To Follow",
		],
		"body": [
			"The power plant near {place} has produced its last kilowatt. Engineers say the boilers and turbines have simply worn out after decades of hard service in desert heat.",
			"Unless a replacement is built, {city} will be running on whatever the rest of the grid can spare. The council has been reminded that a new plant is not free.",
		],
	},
	&"zone_boom": {
		"priority": NOTABLE, "decay": SLOW,
		"headlines": [
			"Building Boom Sweeps {place}",
			"Cranes Outnumber Cacti Near {place}",
			"{count} New Lots Break Ground This Month",
			"Developers Can't Pour Concrete Fast Enough",
			"{city} Grows Another Block Wider",
		],
		"body": [
			"Construction crews reported {count} new lots taking shape around {place} this month. Surveyors' stakes now outnumber the tumbleweeds, which locals say is a first.",
			"Realtors were seen smiling in public. The Dispatch cautions readers that this is not necessarily a good sign, but it is a sign.",
		],
	},
	&"abandonment_wave": {
		"priority": NOTABLE, "decay": SLOW,
		"headlines": [
			"Boarded Windows Multiply Near {place}",
			"{count} Buildings Stand Empty As Tenants Move On",
			"For-Sale Signs Bleach In The Sun At {place}",
			"Tumbleweeds Reclaim A Block Of {city}",
		],
		"body": [
			"Another {count} buildings around {place} were left empty this month. Owners cite a mix of taxes, traffic, crime and the general feeling that the grass is greener anywhere with grass.",
			"The council was asked what it intends to do. Mayor {mayor} said the matter was under review, which is what mayors say.",
		],
	},
	&"chapel_built": {
		"priority": MINOR, "decay": SLOW,
		"headlines": [
			"New Chapel Opens Its Doors Near {place}",
			"Bells Ring Out Over {place} For The First Time",
			"Congregation Raises A Steeple In {city}",
			"Small Chapel, Big Turnout At Dedication",
		],
		"body": [
			"A new chapel was dedicated near {place} this month, built by its congregation with donated lumber and a good deal of stubbornness. The bell was cast locally and rings slightly flat.",
			"The pastor said all are welcome, including gamblers, provided they leave the dice at the door.",
		],
	},
	&"traffic_jam": {
		"priority": NOTABLE, "decay": SLOW,
		"headlines": [
			"Gridlock Grips {place}",
			"Traffic Backed Up Past The City Limits",
			"Commuters Spend Lunch Hour Stuck Near {place}",
			"Honking Now Louder Than The Wind In {city}",
			"{city} Drivers Learn Every Word Of The Radio Jingle",
		],
		"body": [
			"Traffic around {place} reached a standstill this month. One motorist reported finishing a paperback between two intersections.",
			"Engineers suggest more roads, better rail, or fewer people driving to the same place at the same time. The council prefers the option that costs nothing, which does not exist.",
		],
	},
	&"road_decay": {
		"priority": MINOR, "decay": SLOW,
		"headlines": [
			"Potholes Deepen As Road Budget Runs Dry",
			"{count} Stretches Of Road Crumble Near {place}",
			"Drivers Dodge Craters On The Way To Work",
			"Road Crews Idle; Asphalt Isn't",
		],
		"body": [
			"With maintenance funding cut, {count} stretches of road around {place} have crumbled into something closer to gravel. Alignment shops report record business.",
			"The public works department notes that roads do not fix themselves, and that the budget line has been sitting there all along.",
		],
	},
	&"bridge_collapse": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Bridge Near {place} Falls Into The Wash",
			"Span Collapses; No One Hurt, Everyone Late",
			"Neglected Bridge Gives Way At {place}",
			"Engineers Warned, Council Waited, Bridge Went",
		],
		"body": [
			"The bridge near {place} collapsed this month after years of skipped inspections. Traffic now detours the long way round, which in this country is very long indeed.",
			"Nobody was on the span at the time. The bridge fund, residents note, had been zeroed out to pay for other things.",
		],
	},
	&"rail_decay": {
		"priority": MINOR, "decay": SLOW,
		"headlines": [
			"Rails Rust Near {place} As Funding Lapses",
			"Trains Slow To A Crawl On Worn Track",
			"{count} Sections Of Track Pulled From Service",
			"Railroad Ties Rot; Passengers Wait",
		],
		"body": [
			"Rail crews condemned {count} sections of track around {place} this month. Trains are running, but only in the sense that a tortoise runs.",
			"Restoring the maintenance budget would fix it. Restoring the track after that would cost more.",
		],
	},
	&"pollution_alert": {
		"priority": NOTABLE, "decay": SLOW,
		"headlines": [
			"Brown Haze Settles Over {place}",
			"Air Quality Alert Issued For {city}",
			"Sunsets Spectacular, Breathing Optional",
			"Smog Thick Enough To Lean On Near {place}",
		],
		"body": [
			"A haze of factory smoke and exhaust sat over {place} for most of the month. Laundry hung out in the morning came in gray by noon.",
			"Doctors advise staying indoors. Industry advises buying more air conditioners. The council advises patience.",
		],
	},
	&"crime_wave": {
		"priority": NOTABLE, "decay": SLOW,
		"headlines": [
			"Crime Climbs Near {place}; Locks Sell Briskly",
			"Sheriff Reports A Rough Month",
			"Nothing Nailed Down Is Safe In {place}",
			"Burglars Work Harder Than Anyone Else In {city}",
		],
		"body": [
			"The sheriff's office logged a sharp rise in incidents around {place} this month, from lifted hubcaps to a stolen slot machine that was later found working in a barn.",
			"Residents are asking for more patrols. The sheriff is asking for more deputies. Both are asking Mayor {mayor}.",
		],
	},
	&"prison_escape": {
		"priority": MAJOR, "decay": FAST,
		"headlines": [
			"{count} Inmates Walk Away From Overcrowded Prison",
			"Prison Break; Guards Outnumbered And Outrun",
			"Escapees Scatter Into The Desert Near {place}",
			"Warden Requests More Walls, Fewer Prisoners",
		],
		"body": [
			"{count} inmates escaped the prison near {place} this month. With guards stretched thin by overcrowding, the break was less a daring plan than a walk through an open gate.",
			"Search parties are out. Residents are advised to lock their trucks and count their horses.",
		],
	},
	&"status_upgrade": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"{city} Officially A {kind}!",
			"Milestone Reached: {city} Now Ranks As A {kind}",
			"Population Passes {count}; New Signs Ordered",
			"{city} Grows Up; Mayor {mayor} Takes Credit",
			"Cartographers Redraw The Map For {city}",
		],
		"body": [
			"With its population now past {count}, {city} has been reclassified as a {kind}. A ceremony was held at the courthouse, and the punch ran out early.",
			"Mayor {mayor} called it a day for the history books. The Dispatch, which is the history books, has noted it.",
		],
	},
	&"approval_vote": {
		"priority": NOTABLE, "decay": FAST,
		"headlines": [
			"Annual Poll: {count} Percent Approve Of Mayor {mayor}",
			"Voters Weigh In; Mayor {mayor} Scores {count}",
			"Approval Stands At {count} Percent After March Count",
			"Town Hall Straw Poll Delivers A Verdict",
		],
		"body": [
			"The annual approval poll put Mayor {mayor} at {count} percent this year. The top complaint, as ever, was whatever residents had waited longest for.",
			"The mayor's office said the number speaks for itself. Everyone else said it too, meaning different things.",
		],
	},
	&"economy_shift": {
		"priority": NOTABLE, "decay": FAST,
		"headlines": [
			"National Economy Turns; {city} Feels The Draft",
			"Economists Say {kind}; Shopkeepers Say Wait And See",
			"Outlook Shifts To {kind} For The Region",
			"Bank Rate Moves, Ledgers Follow",
		],
		"body": [
			"The national outlook has shifted to {kind}, according to the people paid to say such things. Local factories and shops will feel it over the coming months.",
			"The chamber of commerce urged calm, then quietly checked its savings.",
		],
	},
	&"invention": {
		"priority": MAJOR, "decay": FAST,
		"headlines": [
			"New Technology Arrives: {kind} Now Available",
			"Science Delivers {kind} To {city}",
			"Engineers Unveil {kind}; Council Asks What It Costs",
			"The Future Comes To {city}, One Patent At A Time",
		],
		"body": [
			"Engineers announced that {kind} can now be built in {city}. Demonstrations drew a crowd, mostly because they were held in the shade.",
			"The council has been sent a brochure. The treasurer has been sent an aspirin.",
		],
	},
	&"bankruptcy": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"{city} Broke; Treasury Empty, Creditors Circling",
			"City Declares Bankruptcy",
			"Mayor {mayor} Presides Over An Empty Vault",
			"Bond Holders Arrive; Cash Does Not",
		],
		"body": [
			"The city treasury ran dry this month and {city} has declared itself bankrupt. Bond interest went unpaid, services were cut, and the courthouse clock was pawned for scrap.",
			"Mayor {mayor} faces a hard year. The Dispatch, unpaid for its municipal notices, will continue publishing out of spite.",
		],
	},
	&"disaster_started": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Disaster Strikes {city}: {kind} Near {place}",
			"{kind} Hits {place}; Emergency Declared",
			"Sirens Wail As {kind} Sweeps {city}",
			"Crews Race To {place} After {kind}",
		],
		"body": [
			"A {kind} struck {city} near {place} this month. Emergency crews were dispatched as residents fled to higher ground, lower ground, or the nearest bar, depending on temperament.",
			"Damage is still being counted. Mayor {mayor} asked residents to stay calm and keep the roads clear for responders.",
		],
	},
	&"disaster_fire": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Fire Breaks Out Near {place}",
			"Blaze Spreads Through {place}; Crews Scramble",
			"Smoke Over {city} As Fire Jumps The Street",
			"Dry Wind Feeds Flames Near {place}",
		],
		"body": [
			"A fire broke out near {place} and, helped along by the wind, spread faster than the volunteers could unroll hose. Several buildings are gone and more are threatened.",
			"Firefighters ask residents to stay away and, for once, not to bring lawn chairs.",
		],
	},
	&"disaster_flood": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Flash Flood Roars Through {place}",
			"Dry Wash Turns River; {place} Under Water",
			"Water Rises In {city}; Sandbags Sell Out",
			"The Rain Came All At Once",
		],
		"body": [
			"A wall of water came down the wash and into {place} this month. Cars were carried a block, porches floated free, and one canoe made an appearance nobody could explain.",
			"The water will recede. The mud, old-timers warn, will not.",
		],
	},
	&"disaster_tornado": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Twister Tears Across {place}",
			"Tornado Touches Down In {city}",
			"Funnel Cloud Rearranges {place}",
			"Roofs Airborne As Tornado Passes Through",
		],
		"body": [
			"A tornado touched down near {place} and cut a ragged line across town before lifting back into the sky. Roofs, fences and at least one outhouse were relocated without permits.",
			"Nobody in {city} had seen one before, and most would prefer not to again.",
		],
	},
	&"disaster_earthquake": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Earthquake Shakes {city}; Fires Follow",
			"Ground Heaves Near {place}",
			"Tremor Topples Buildings, Cracks Roads",
			"{city} Rattled By Quake; Aftershocks Feared",
		],
		"body": [
			"The ground shook under {city} this month, hardest near {place}. Walls cracked, gas lines ruptured, and fires broke out where the shaking was worst.",
			"Geologists say the fault has always been there. Residents say they would have appreciated a mention earlier.",
		],
	},
	&"disaster_monster": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Tsawhawbitts Stomps Through {place}",
			"Tsawhawbitts Sighted; {city} Advises Staying Indoors",
			"Tsawhawbitts Is Walking Down Main Street",
			"Tsawhawbitts Flattens {place}; Scientists Baffled, Locals Less So",
		],
		"body": [
			"Tsawhawbitts walked out of the desert and through {place} this month. The enormous giant appeared to be looking for something and did not find it.",
			"Tsawhawbitts left the way he came. The buildings he stepped on did not.",
		],
	},
	&"disaster_riot": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Riot Breaks Out Near {place}",
			"Crowd Turns Ugly In {city}; Windows Pay The Price",
			"Unrest Spreads From {place}",
			"Police Call For Backup As Riot Grows",
		],
		"body": [
			"A crowd near {place} turned into a riot this month. Windows were broken, cars were overturned, and a great deal was said about the council that cannot be printed.",
			"Police have asked for reinforcements. Mayor {mayor} has asked what started it, which is a longer conversation.",
		],
	},
	&"disaster_plane_crash": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Aircraft Comes Down Near {place}",
			"Plane Crash Sparks Fires In {city}",
			"Wreckage Scattered Across {place}",
			"Pilot Missed The Runway By Some Distance",
		],
		"body": [
			"An aircraft came down near {place} this month, starting fires where it hit. Crews worked through the night to keep the flames from spreading.",
			"Investigators are on their way. The airport says its runway is fine and was, in fact, right over there.",
		],
	},
	&"disaster_hurricane": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Hurricane Batters {city}",
			"Storm Surge Swamps {place}",
			"Winds Howl, Water Rises Along The Shore",
			"Hurricane Makes Landfall; {city} Boards Up",
		],
		"body": [
			"A hurricane came ashore this month, driving water into {place} and wind through everything else. Palms bent double and signs went sailing.",
			"The storm has passed. The cleanup, the council is told, has not started.",
		],
	},
	&"disaster_meltdown": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Meltdown At Nuclear Plant Near {place}",
			"Radiation Leak Forces Evacuation",
			"Reactor Fails; {city} Told To Stay Clear Of {place}",
			"Glow Over {place} Not The Good Kind",
		],
		"body": [
			"The reactor near {place} suffered a meltdown this month. Ground around the plant is contaminated and will stay that way for longer than anyone reading this will live.",
			"The utility called it an isolated incident. Residents called it several other things.",
		],
	},
	&"disaster_chemical_spill": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Chemical Spill Poisons Ground Near {place}",
			"Tanker Ruptures; {place} Cordoned Off",
			"Toxic Leak Spreads Through {city} Soil",
			"Something Green Is Seeping Out Of {place}",
		],
		"body": [
			"A chemical spill near {place} has left the ground contaminated and the air sharp enough to taste. Crews in heavy suits are working the site.",
			"The company responsible has issued a statement. It is very short.",
		],
	},
	&"disaster_microwave": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Orbiting Beam Misses Its Target, Hits {place}",
			"Microwave Receiver Scorches Neighborhood",
			"Sky Beam Goes Astray; Fires Near {place}",
			"Power From Space Arrives Somewhat Off Course",
		],
		"body": [
			"The satellite that feeds the microwave receiver lost its aim this month and cooked a stretch of {place} instead. Fires followed, and so did a great many questions.",
			"Engineers say the beam has been recalibrated. Residents near the plant have bought hats.",
		],
	},
	&"disaster_volcano": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Volcano Erupts Near {place}!",
			"New Mountain Rises Over {city}",
			"Lava And Ash Bury {place}",
			"The Ground Opened Up And Nobody Was Consulted",
		],
		"body": [
			"A volcano erupted near {place} this month, raising a new mountain where there was none and burying everything on its slopes in ash and lava.",
			"Geologists are thrilled. Nobody else is.",
		],
	},
	&"disaster_firestorm": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Firestorm Engulfs {city}",
			"Fires Break Out Across Town At Once",
			"Wind-Driven Blazes Overwhelm Crews",
			"{city} Burns From {place} Outward",
		],
		"body": [
			"Fires broke out across {city} at once this month, fanned by a hot wind that turned each one into a front. Crews near {place} fought through the night.",
			"The sky was orange until dawn. The Dispatch office is fine, thank you for asking.",
		],
	},
	&"disaster_mass_riots": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Riots Erupt Across {city}",
			"Unrest Spreads From {place} To Every Corner Of Town",
			"Mass Riots Grip {city}; Guard Requested",
			"Whole Districts Take To The Streets",
		],
		"body": [
			"Riots broke out in several districts of {city} at once this month, worst near {place}. Fires were set and storefronts emptied before police could form a line.",
			"Mayor {mayor} has requested outside help. The council has requested the mayor.",
		],
	},
	&"disaster_major_flood": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Great Flood Swallows Low Ground Across {city}",
			"Rivers Leave Their Banks; {place} Submerged",
			"Worst Flood In Living Memory Hits {city}",
			"Water Everywhere, And Rising",
		],
		"body": [
			"The worst flood anyone can remember spread across the low ground of {city} this month, drowning {place} and everything at its level.",
			"Boats were seen on the main road. Some of them were being used correctly.",
		],
	},
	&"disaster_hazard": {
		"priority": URGENT, "decay": ONCE,
		"headlines": [
			"Hazardous Site Discovered Near {place}",
			"Contamination Found Under {place}",
			"Toxic Ground Fenced Off In {city}",
			"Old Dump Turns Out To Be Worse Than Advertised",
		],
		"body": [
			"Inspectors found hazardous contamination near {place} this month and fenced the site off. Nothing can be built there until it is cleaned, and cleaning is not cheap.",
			"The previous owner could not be reached, having moved to another state and possibly another name.",
		],
	},
	&"disaster_ended": {
		"priority": MAJOR, "decay": FAST,
		"headlines": [
			"{kind} Over; {city} Counts The Cost",
			"All Clear Sounded After {kind}",
			"Crews Stand Down As {kind} Ends",
			"{city} Begins Cleanup From {kind}",
		],
		"body": [
			"The {kind} that struck {city} is over. Crews have stood down and residents are picking through what is left, which in places is not much.",
			"Rebuilding will take money the council may or may not have. Mayor {mayor} has promised a plan.",
		],
	},
	&"fire_reported": {
		"priority": MAJOR, "decay": FAST,
		"headlines": [
			"Fire Reported Near {place}",
			"Smoke Spotted Over {place}; Crews Roll",
			"Small Blaze Threatens Block In {city}",
			"Brush Fire Creeps Toward {place}",
		],
		"body": [
			"A fire was reported near {place} this month. Crews responded and are working to keep it from spreading to the neighbors, who are watching closely with garden hoses.",
			"Residents are reminded that the dry season is every season here.",
		],
	},
	&"reward_offered": {
		"priority": MAJOR, "decay": FAST,
		"headlines": [
			"Grateful Citizens Offer {city} A {kind}",
			"{kind} Proposed As Thanks To Mayor {mayor}",
			"Council Invited To Build A {kind}",
			"Town Earns Itself A {kind}",
		],
		"body": [
			"In recognition of how far {city} has come, citizens have offered to raise a {kind} wherever Mayor {mayor} sees fit. The land is the council's to choose.",
			"Ribbon-cutting scissors have been ordered. They are not cheap either.",
		],
	},
	&"exodus": {
		"priority": MAJOR, "decay": FAST,
		"headlines": [
			"Residents Leave {city} In Droves",
			"{count} Families Pack Up And Head Out",
			"Moving Vans Outnumber Delivery Trucks This Month",
			"Population Drops As {city} Loses Its Shine",
		],
		"body": [
			"Some {count} families left {city} this month, citing everything from taxes to traffic to the smell downwind of the plant. The moving companies are the one growth industry.",
			"Mayor {mayor} says the city will bounce back. The people leaving say the same thing about wherever they are going.",
		],
	},
	# Four headlines, like exodus, so the headline pick draws from the same range.
	&"resort_launch": {
		"priority": MAJOR, "decay": FAST,
		"headlines": [
			"{city}'s Gaming Resorts Lift Off For The Stars",
			"{count} Residents Depart Aboard Departing Resorts",
			"The Strip Takes Flight Over {city}",
			"Resorts Rise Into The Sky; Rubble Left Behind",
		],
		"body": [
			"The gaming resorts of {city} sealed their doors and rose into the sky this month, carrying {count} residents with them. Rubble and a modest refund are all they left behind.",
			"Mayor {mayor} watched the launch from the courthouse steps. The council is already arguing over what to build on the empty lots.",
		],
	},
	&"neighbor_news": {
		"priority": MINOR, "decay": SLOW,
		"headlines": [
			"News From Down The Road: {place} Grows",
			"Neighboring {place} Reports A Busy Month",
			"Across The County Line, {place} Makes Plans",
			"{place} Sends Regards And A Trade Proposal",
		],
		"body": [
			"Word arrived from {place}, our neighbor down the highway, of growth and ambition over there. Their population and ours now trade back and forth across the line.",
			"Relations remain cordial. Their football team is another matter.",
		],
	},
	&"neighbor_growth": {
		"priority": MINOR, "decay": SLOW,
		"headlines": [
			"{place} Passes {count} Residents",
			"Neighbor {place} Booms; Commuters Follow",
			"Growth Next Door In {place}",
		],
		"body": [
			"Our neighbor {place} now counts more than {count} residents, and some of them work here. The highway between the towns is busier every month.",
			"The Dispatch congratulates {place} and reminds it who was here first.",
		],
	},
	&"neighbor_connection": {
		"priority": NOTABLE, "decay": SLOW,
		"headlines": [
			"Road Now Runs Through To {place}",
			"{city} And {place} Joined By New Link",
			"Border Crossing Opens Toward {place}",
		],
		"body": [
			"A new connection now carries traffic between {city} and {place}. Goods, workers and gossip are expected to flow in both directions.",
			"A ribbon was cut at the county line. It was a windy day and the ribbon is now in {place}.",
		],
	},
	&"water_shortage": {
		"priority": MAJOR, "decay": FAST,
		"headlines": [
			"Taps Run Dry In {count} Buildings",
			"Water Shortage Hits {city}; Pumps Can't Keep Up",
			"Lawns Brown, Tempers Short As Water Falls Short",
			"Well, Well, Well: {city} Needs More Of Them",
		],
		"body": [
			"Pumping capacity fell short of demand this month and {count} buildings went without water. Swimming pools are down to a puddle and the car wash is closed.",
			"The water board recommends more pumps, more pipes, or more rain. Two of those are on the budget.",
		],
	},
	&"tax_change": {
		"priority": NOTABLE, "decay": FAST,
		"headlines": [
			"Tax Rate Set At {count} Percent",
			"Council Adjusts Taxes; Wallets Adjust Accordingly",
			"New Rates Announced For {city}",
			"Taxes Move; Grumbling Follows",
		],
		"body": [
			"The council set the tax rate at {count} percent this month. Shopkeepers and homeowners did the arithmetic on napkins and reached the usual conclusions.",
			"Mayor {mayor} said the rate reflects the city's needs. Residents said it reflects the mayor's.",
		],
	},
	&"ordinance_passed": {
		"priority": NOTABLE, "decay": FAST,
		"headlines": [
			"Council Passes {kind} Ordinance",
			"New Law On The Books: {kind}",
			"{city} Adopts {kind} Measure",
			"Ordinance Vote: {kind} Carries",
		],
		"body": [
			"The council adopted the {kind} ordinance this month after a debate that ran long enough for the coffee to go cold twice. It takes effect at once.",
			"Supporters call it overdue. Opponents call it something else. The clerk calls it filed.",
		],
	},
	&"bond_issued": {
		"priority": NOTABLE, "decay": FAST,
		"headlines": [
			"{city} Borrows {count} Against Its Future",
			"Bond Issued; Interest Due Every January",
			"Council Signs For A {count} Bond",
			"Treasury Tops Up With Borrowed Money",
		],
		"body": [
			"The council issued a bond of {count} this month to keep the treasury above water. Interest will come due every January for as long as the bond stands.",
			"The treasurer described the terms as reasonable. The treasurer will not be here when they come due.",
		],
	},
	&"power_restored": {
		"priority": MINOR, "decay": FAST,
		"headlines": [
			"Lights Back On Across {city}",
			"Power Restored; Ice Cream Sales Resume",
			"Grid Catches Up; Brownout Over",
		],
		"body": [
			"Generating capacity has caught up with demand and every building in {city} has power again. The candle shop reports a sudden drop in trade.",
			"The utility board thanked residents for their patience and asked them not to buy any more air conditioners this week.",
		],
	},
	&"water_restored": {
		"priority": MINOR, "decay": FAST,
		"headlines": [
			"Water Flows Again In {city}",
			"Taps Run Clear; Lawns Sigh With Relief",
			"Pumps Catch Up; Shortage Ends",
		],
		"body": [
			"The pumps are keeping up again and water service has returned to every building in {city}. The car wash reopened to a line around the block.",
			"The water board reminds residents that the desert has not moved and the next dry spell is on its way.",
		],
	},
	&"treasury_deficit": {
		"priority": MAJOR, "decay": FAST,
		"headlines": [
			"{city} Spends More Than It Takes In",
			"Books Close In The Red For {year}",
			"Treasury Shrinks; Council Eyes The Bond Desk",
			"Deficit Year For {city}; Treasurer Sharpens Pencil",
		],
		"body": [
			"The city closed its books for {year} with a deficit, leaving the treasury at {count}. Costs outran taxes, which is easy to do and hard to undo.",
			"Options on the table include higher taxes, lower funding, or a bond. Mayor {mayor} was seen studying all three and enjoying none.",
		],
	},
	&"port_opened": {
		"priority": NOTABLE, "decay": FAST,
		"headlines": [
			"{kind} Opens For Business Near {place}",
			"First Cargo Moves Through New {kind}",
			"{city} Gets Its {kind}; Horizons Widen",
			"New {kind} Draws Crowd, Dust, Optimism",
		],
		"body": [
			"The new {kind} near {place} handled its first traffic this month. Freight, passengers and the occasional lost tourist are now moving through {city}.",
			"Local business expects the trade to follow. Local birds expect nothing good.",
		],
	},
	&"port_closed": {
		"priority": NOTABLE, "decay": FAST,
		"headlines": [
			"{kind} Near {place} Falls Silent",
			"No Traffic At {city} {kind}; Gates Locked",
			"{kind} Shuts Down; Weeds Move In",
		],
		"body": [
			"The {kind} near {place} has stopped operating. Whether for want of power, water or customers, nothing is moving through it and the gates are chained.",
			"The chamber of commerce called it temporary. The weeds called it home.",
		],
	},
	&"plant_aging": {
		"priority": NOTABLE, "decay": SLOW,
		"headlines": [
			"{kind} Near {place} Nears End Of Service Life",
			"Engineers Warn Old Plant Won't Last Forever",
			"Aging {kind} Put On Watch List",
			"Plant Near {place} Is {count} Years Old And Feeling It",
		],
		"body": [
			"Inspectors report that the {kind} near {place} is showing its age at {count} years. It still runs, but the engineers use the word still with some emphasis.",
			"The council has been advised to budget for a replacement before the plant decides the matter itself.",
		],
	},
	&"plant_replaced": {
		"priority": NOTABLE, "decay": FAST,
		"headlines": [
			"Worn-Out {kind} Rebuilt Near {place}",
			"City Pays To Replace Aging Plant",
			"New Boilers For Old: {kind} Renewed",
		],
		"body": [
			"The {kind} near {place} reached the end of its life and was rebuilt on the spot at city expense. The lights stayed on, which was the point.",
			"The treasurer noted the bill and said nothing, loudly.",
		],
	},
	&"neighbor_shock": {
		"priority": NOTABLE, "decay": FAST,
		"headlines": [
			"Upheaval In {place} Rattles The Region",
			"Neighbor {place} Has A Very Bad Month",
			"Trouble Next Door: {place} Reels",
			"Word From {place} Is Not Good",
		],
		"body": [
			"Our neighbor {place} suffered a sudden setback this month, the details of which vary with the teller. Trade across the line has slowed while they sort themselves out.",
			"{city} has offered help. {place} has offered thanks and a request for lumber.",
		],
	},
	&"city_milestone": {
		"priority": MAJOR, "decay": FAST,
		"headlines": [
			"{city} Earns The Right To A {kind}",
			"Milestone: {kind} Now Available To Council",
			"Population Passes {count}; {kind} Offered",
			"Citizens Reward Growth With A {kind}",
		],
		"body": [
			"With {city} past {count} residents, the council may now build a {kind}. Citizens consider it earned; the treasurer considers it expensive.",
			"A site has not been chosen. Several residents have opinions about their own street.",
		],
	},
	&"birth_record": {
		"priority": MINOR, "decay": SLOW,
		"headlines": [
			"Record {count} Births In {city} This Year",
			"Maternity Ward Busiest On Record",
			"Baby Boom: {count} New Residents Arrive The Old-Fashioned Way",
			"Cradles Sell Out As Births Hit {count}",
		],
		"body": [
			"The hospital logged {count} births this year, more than any year on record. The maternity ward has requested a second rocking chair.",
			"The school board has done the arithmetic and gone quiet.",
		],
	},
	&"advisor_need": {
		"priority": MINOR, "decay": SLOW,
		"headlines": [
			"Advisors Press Council On {kind}",
			"{kind}: The Word From The Advisors' Office",
			"Council Told {kind} Can't Wait",
		],
		"body": [
			"The advisors' office delivered its monthly memorandum on {kind} to Mayor {mayor}. It was short, underlined, and left on top of the pile.",
			"The mayor's office confirmed receipt. Residents confirmed the problem.",
		],
	},
}

## Kinds reported under another name that share a template.
const ALIASES: Dictionary = {
	&"ordinance_enacted": &"ordinance_passed",
}

## Human-interest fillers for slow months.
const FILLERS: Array = [
	{"headline": "Casino Opens With Free Peanuts, Paid Everything Else", "body": "A new casino opened on the strip with a brass band, a searchlight and a buffet that ran out by nine. Management called the evening a success. Patrons called it Tuesday."},
	{"headline": "Heat Wave Enters Third Week; Sidewalks Fry Eggs, Reporters Confirm", "body": "Temperatures held above anything reasonable for a third week. The Dispatch tested the sidewalk-egg theory and can report that it works, if you like your eggs with grit."},
	{"headline": "Jackrabbit Population Booms; Gardeners Despair", "body": "A wet spring has produced more jackrabbits than anyone can count, and they are eating everything green within city limits. One resident has begun naming them, which is not a solution."},
	{"headline": "Annual Chili Cook-Off Won By Same Man For Ninth Year", "body": "The chili cook-off was won again by the same fellow with the same recipe, which he will not share. Second place was awarded to a pot that a judge described as brave."},
	{"headline": "Giant Fiberglass Cactus Draws Visitors, Confuses Birds", "body": "The roadside cactus on the highway into town is now the tallest thing for miles. Motorists stop for photographs and birds stop to be disappointed."},
	{"headline": "Dust Storm Sandblasts Every Windshield In Town", "body": "A wall of dust rolled through on Thursday and left every car in {city} the same shade of tan. The car wash is booked for a month."},
	{"headline": "Local Man Claims To Have Seen Rain; Others Skeptical", "body": "A resident reports seeing rain fall on the north end of town. Nobody else saw it, the ground was dry by the time anyone looked, and the matter has been referred to the weather office."},
	{"headline": "Lizard Races Return To The Fairgrounds", "body": "The annual lizard races drew a full grandstand this year. The favorite refused to leave the starting line, which is understandable in this heat."},
	{"headline": "Diner Adds Second Fan; Customers Weep With Gratitude", "body": "The diner on Main Street has installed a second ceiling fan. Regulars describe the difference as life-changing. The pie is unchanged."},
	{"headline": "Ghost Town Tour Canceled After Ghost Town Gets Residents", "body": "The weekly tour of the abandoned settlement up the road has been called off, as three families have moved in and object to being photographed."},
	{"headline": "Rodeo Weekend Leaves Town Sore But Happy", "body": "Rodeo weekend came and went with the usual mix of bruises, dust and sunburn. The bull, which has a name, was declared the winner again."},
	{"headline": "Neon Sign Repaired; Now Reads Correctly For First Time In Years", "body": "The motel sign that has read MOT L since anyone can remember has been fixed. Longtime residents say it looks wrong."},
	{"headline": "Tumbleweed The Size Of A Truck Rolls Through Downtown", "body": "A tumbleweed of unusual size crossed downtown on Sunday, paused at a stop sign, and continued east. Witnesses agree it had the right of way."},
	{"headline": "Cactus Blooms Overnight; Town Turns Out To Look", "body": "The night-blooming cactus outside the library opened at last, and half of {city} stood around it in bathrobes. It closed by morning, as is its habit."},
	{"headline": "Well-Digging Contest Ends In Draw, Mud", "body": "The well-digging contest at the fair ended when both teams struck water at the same moment and then each other. No winner was declared, but everyone was clean for once."},
	{"headline": "Scorpion Found In Boot; Boot Found In Yard", "body": "A resident discovered a scorpion in his boot on Monday morning. The boot was last seen traveling at speed across the lawn. Both are recovering."},
	{"headline": "Old Mine Shaft Fenced Off After Goat Incident", "body": "The mine shaft east of town has been fenced after a goat was retrieved from it for the third time. The goat is fine and appears to enjoy the attention."},
	{"headline": "Barbershop Quartet Now A Trio; Tenor Moved To The Coast", "body": "The town quartet has lost its tenor to a job on the coast. Auditions are open. Applicants are warned that the repertoire is mostly about trains."},
	{"headline": "Sunset Declared Best Of The Year By Committee", "body": "The sunset committee met on the ridge on Friday and declared this year's best. Minutes record it as orange with purple, which narrows it down somewhat."},
	{"headline": "Motel Pool Refilled; Children Appear From Nowhere", "body": "The motel pool was refilled for the season, and within an hour it held more children than the town has on record. The manager has stopped asking for room numbers."},
	{"headline": "Water Tower Repainted; Town Name Spelled Right This Time", "body": "The water tower received a fresh coat of paint and, after some discussion, the correct spelling of {city}. The painter blamed the wind for last time."},
	{"headline": "Fishing Derby Held At Reservoir; Fish Decline To Participate", "body": "The fishing derby went ahead despite the fish, who kept to the deep end. The prize for largest catch went to a hat."},
	{"headline": "Mystery Hum Traced To Refrigerator At The Feed Store", "body": "The low hum that has puzzled the east side for a month has been traced to a refrigerator at the feed store. It has been switched off and the mystery is over, to general disappointment."},
	{"headline": "Old-Timers Bench Gets New Slat; Old-Timers Suspicious", "body": "The bench outside the courthouse has a new slat. Its regular occupants tested it for an afternoon and concluded that it will do, for now."},
	{"headline": "Radio Station Adds Second Record", "body": "The local station has acquired a second record and will alternate it with the first. Listeners are advised that the second one is a waltz."},
	{"headline": "Hot Springs Reopen; Smell Described As Character", "body": "The hot springs south of town reopened after repairs. Visitors are reminded that the smell is natural, historic, and part of the experience."},
	{"headline": "Stray Burro Adopted By Fire Station", "body": "A burro that wandered into the fire station has been adopted by the crew. It answers to Chief and has already been photographed in a helmet."},
	{"headline": "Chili Cook-Off Judge Recovers; Vows To Return", "body": "The judge hospitalized after last month's cook-off has recovered and says he will be back next year. His doctor has other views."},
	{"headline": "Hardware Store Sells Out Of Shade Cloth In One Afternoon", "body": "A shipment of shade cloth lasted about four hours at the hardware store on Saturday. The owner has ordered more and a rope for the queue."},
	{"headline": "High School Team Wins By Forfeit; Other Team Lost In Desert", "body": "The visiting team took a wrong turn on the way to Friday's game and was found by a rancher some hours later. The home side has claimed the win and a photograph of the tumbleweed they blame."},
	{"headline": "Petrified Log Returned To Roadside Attraction After Forty Years", "body": "A petrified log taken from the roadside attraction decades ago arrived by post with an apology. The attraction has put it back and framed the letter."},
	{"headline": "Town Clock Repaired; Runs Fast Out Of Enthusiasm", "body": "The courthouse clock has been repaired and now gains a minute a day. The clockmaker says it will settle down once it gets used to the heat."},
	{"headline": "Drive-In Reopens With Double Feature And Single Speaker", "body": "The drive-in screened its first films in years to a full lot. The one working speaker was placed in the middle and people parked around it like a campfire."},
	{"headline": "Mineral Springs Water Now Bottled; Tastes Like Nickels", "body": "A local outfit has begun bottling the mineral springs water. The label promises vitality. The taste promises pocket change."},
	{"headline": "Coyotes Serenade East Side For Third Straight Night", "body": "Residents of the east side report three nights of coyote song. Opinions are divided on the harmonies but not on the volume."},
	{"headline": "Farmers' Market Opens; Mostly Melons, Mostly Fine", "body": "The Saturday market opened for the season with a strong showing of melons and one table of jam. Attendance was high, as was the temperature."},
	{"headline": "Painted Rock On Hill Repainted; Now Also Wrong Color", "body": "The big rock on the hill was repainted overnight by persons unknown. The council has decided that this year's color is the official one until someone changes it."},
	{"headline": "Gas Station Adds Ice Machine; Traffic Jam Follows", "body": "The gas station at the edge of town installed an ice machine and immediately caused the largest traffic jam in {city} history. Police describe the crowd as orderly and damp."},
	{"headline": "Bingo Night Moved To Larger Hall After Standing-Room Crowd", "body": "Wednesday bingo has outgrown the church basement and will move to the grange hall. The caller has been given a microphone and a warning about volume."},
	{"headline": "Retired Prospector Finds Nothing, Reports Good Day", "body": "A retired prospector returned from the hills with an empty sack and a broad smile. Asked what he found, he said quiet, and recommended it."},
	{"headline": "Windmill Squeak Finally Oiled; Town Can't Sleep Without It", "body": "The windmill by the stockyard has been oiled after years of squeaking. Several residents report insomnia and have asked for it to be put back the way it was."},
	{"headline": "Swap Meet Trades Same Lamp For Fifth Year Running", "body": "A brass lamp changed hands again at the swap meet and is now believed to have lived in every house on the west side. Its current owner intends to keep it, which nobody believes."},
	{"headline": "Mayor {mayor} Cuts Ribbon; Scissors Also Cut Mayor", "body": "The ribbon-cutting at the new bench went ahead with a minor injury to Mayor {mayor}, who described the scissors as sharper than expected. The bench is open."},
	{"headline": "Snow Falls On {city}; Nobody Owns A Shovel", "body": "A rare snowfall dusted {city} overnight and was gone by lunch. In the interval, residents photographed it, tasted it, and looked for a shovel that does not exist."},
]

## Words for a map position, so a story can say roughly where it happened.
const DISTRICTS: Array[String] = [
	"the northwest corner", "the north end", "the northeast corner",
	"the west side", "downtown", "the east side",
	"the southwest corner", "the south end", "the southeast corner",
]

const PLACEHOLDERS: Array[String] = ["city", "mayor", "year", "count", "place", "kind"]


static func kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in STORIES:
		out.append(k)
	return out


static func has(kind: StringName) -> bool:
	return STORIES.has(kind)


## The template a report resolves to. Disaster reports pick their own kind's
## template when one exists; unknown kinds fall back to the generic story.
static func template_key(kind: StringName, args: Dictionary = {}) -> StringName:
	if kind == &"disaster_started" and args.has("kind"):
		var specific := StringName("disaster_" + String(args["kind"]))
		if STORIES.has(specific):
			return specific
	if kind == &"military_base":
		return &"military_base_accepted" if bool(args.get("accepted", false)) else &"military_base_declined"
	if STORIES.has(kind):
		return kind
	if ALIASES.has(kind):
		return ALIASES[kind]
	return GENERIC


static func priority_of(kind: StringName, args: Dictionary = {}) -> int:
	var t: Dictionary = STORIES[template_key(kind, args)]
	return int(t["priority"])


static func decay_of(kind: StringName, args: Dictionary = {}) -> int:
	var t: Dictionary = STORIES[template_key(kind, args)]
	return int(t["decay"])


static func headline_variants(kind: StringName, args: Dictionary = {}) -> Array:
	var t: Dictionary = STORIES[template_key(kind, args)]
	return t["headlines"]


static func body_paragraphs(kind: StringName, args: Dictionary = {}) -> Array:
	var t: Dictionary = STORIES[template_key(kind, args)]
	return t["body"]


## A filled headline for the report, picked at random among the variants.
static func headline(kind: StringName, args: Dictionary, values: Dictionary, rng: SimRng) -> String:
	var variants := headline_variants(kind, args)
	var text: String = variants[rng.below(variants.size())]
	return fill(text, values, true)


## The filled body: every paragraph of the template, joined by blank lines.
static func body(kind: StringName, args: Dictionary, values: Dictionary) -> String:
	var parts: Array[String] = []
	for p in body_paragraphs(kind, args):
		parts.append(sentence_case(fill(String(p), values)))
	return "\n\n".join(parts)


## Reports about the whole city: without a location they happen in the city
## itself rather than at "the edge of town".
const CITY_WIDE_KINDS: Array[StringName] = [&"zone_boom", &"crime_wave", &"pollution_alert",
	&"traffic_jam", &"abandonment_wave"]
const EDGE_OF_TOWN := "the edge of town"


## Placeholder values for a report, from its args and the city.
static func values_for(kind: StringName, args: Dictionary, city_name: String, mayor: String, year: int) -> Dictionary:
	var fallback := EDGE_OF_TOWN
	if kind in CITY_WIDE_KINDS and not city_name.strip_edges().is_empty():
		fallback = city_name
	return {
		"city": city_name,
		"mayor": mayor,
		"year": str(year),
		"count": count_text(args),
		"place": place_text(args, fallback),
		"kind": kind_text(kind, args),
	}


const COUNT_KEYS: Array[String] = ["count", "amount", "population", "value", "unpowered", "unwatered",
	"tiles", "births", "approval", "residents", "age_years", "level", "average", "funds", "cost"]
## Count keys that hold dollars and print with a sign and "$".
const MONEY_KEYS: Array[String] = ["amount", "funds", "cost"]
const PLACE_KEYS: Array[String] = ["at", "center", "tile", "anchor"]
const KIND_KEYS: Array[String] = ["kind", "name", "key", "family", "technology", "category"]


static func count_text(args: Dictionary) -> String:
	for k in COUNT_KEYS:
		if args.has(k):
			var v: Variant = args[k]
			if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				return NoticeLines.money(int(v)) if k in MONEY_KEYS else _grouped(int(v))
			return String(v)
	return "several"


## Where a report happened. An explicit place wins, then a map position. A
## name is the place only when nothing locates the report: a power plant's name
## and anchor describe the plant itself, so its place is the anchor's district.
static func place_text(args: Dictionary, fallback: String = EDGE_OF_TOWN) -> String:
	if args.has("place") and _is_text(args["place"]):
		return String(args["place"])
	if args.has("x") and args.has("y"):
		return place_name(Vector2i(int(args["x"]), int(args["y"])))
	for k in PLACE_KEYS:
		if args.has(k):
			var p := position_of(args[k])
			if p.x >= 0:
				return place_name(p)
	if args.has("name") and _is_text(args["name"]):
		return String(args["name"])
	return fallback


static func _is_text(v: Variant) -> bool:
	return typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME


## A map position from a Vector2i, an [x, y] array or an "x,y" string.
static func position_of(v: Variant) -> Vector2i:
	match typeof(v):
		TYPE_VECTOR2I:
			return v
		TYPE_VECTOR2:
			return Vector2i(v)
		TYPE_ARRAY:
			if v.size() == 2:
				return Vector2i(int(v[0]), int(v[1]))
		TYPE_STRING:
			return SimSystem.parse_tile_key(v)
	return Vector2i(-1, -1)


static func kind_text(kind: StringName, args: Dictionary) -> String:
	if args.has("need"):
		return AdvisorLines.title(AdvisorLines.normalize(StringName(String(args["need"]))))
	for k in KIND_KEYS:
		if not args.has(k):
			continue
		var v: Variant = args[k]
		if k == "kind" and kind in [&"port_opened", &"port_closed"] and typeof(v) == TYPE_INT:
			return String(Zones.NAMES.get(v, "Port"))
		if k == "name" and typeof(v) == TYPE_STRING:
			return String(v)
		if k == "key":
			return reward_name(StringName(str(v)))
		return kind_label(StringName(str(v)))
	return kind_label(kind)


## A readable label for a kind: underscores become spaces, words capitalised.
## Disaster kinds use their player-facing names.
static func kind_label(kind: StringName) -> String:
	if kind in DisasterParams.KINDS:
		return DisasterParams.display_name(kind)
	return String(kind).replace("_", " ").capitalize()


## The display name of a gift or milestone key: a building's own name, or
## "Military Base" for the base proposal.
static func reward_name(key: StringName) -> String:
	if key == RewardParams.MILITARY_KEY:
		return "Military Base"
	var id := Buildings.id_of(key)
	if id != Buildings.NONE:
		return Buildings.display_name(id)
	return kind_label(key)


## A district name for a map position, by thirds of the map.
static func place_name(p: Vector2i) -> String:
	var col := clampi(p.x * 3 / City.WIDTH, 0, 2)
	var row := clampi(p.y * 3 / City.HEIGHT, 0, 2)
	return DISTRICTS[row * 3 + col]


## Replace every known placeholder; unknown braces are left in place so tests
## can catch them. Headlines are Title Case, so filled districts and the
## "several" stand-in are capitalised there too.
static func fill(text: String, values: Dictionary, headline: bool = false) -> String:
	var out := text
	if values.has("mayor") and is_unnamed_mayor(String(values["mayor"])):
		out = without_mayor_name(out, headline)
	for key in PLACEHOLDERS:
		if values.has(key):
			var value := String(values[key])
			if headline and key in ["place", "count"] and _is_lowercase_phrase(value):
				value = title_case(value)
			out = out.replace("{" + key + "}", value)
	return out


## Whether the mayor has no name of their own: blank or the default "Mayor".
static func is_unnamed_mayor(mayor: String) -> bool:
	var m := mayor.strip_edges()
	return m.is_empty() or m.to_lower() == "mayor"


## Text with "Mayor {mayor}" (and any lone {mayor}) written as "the mayor":
## "The mayor" at the start of a sentence, "The Mayor" in a headline.
static func without_mayor_name(text: String, headline: bool) -> String:
	var out := text
	for token in ["Mayor {mayor}", "{mayor}"]:
		var at := out.find(token)
		while at >= 0:
			var phrase := "the mayor"
			if headline:
				phrase = "The Mayor"
			elif _starts_sentence(out, at):
				phrase = "The mayor"
			out = out.substr(0, at) + phrase + out.substr(at + token.length())
			at = out.find(token, at + phrase.length())
	return out


static func _starts_sentence(text: String, at: int) -> bool:
	var i := at - 1
	while i >= 0 and text[i] == " ":
		i -= 1
	return i < 0 or text[i] in [".", "!", "?", "\n", "\"", ":"]


## Lowercase stand-ins such as "the north end" or "several"; proper names and
## numbers are left as they are.
static func _is_lowercase_phrase(value: String) -> bool:
	return not value.is_empty() and value[0] != value[0].to_upper()


## Every word starting with a capital letter: "the north end" -> "The North End".
static func title_case(value: String) -> String:
	var words := value.split(" ")
	for i in words.size():
		if not words[i].is_empty():
			words[i] = words[i][0].to_upper() + words[i].substr(1)
	return " ".join(words)


## A paragraph that starts with a capital letter, for stand-ins such as
## "several" that can open a sentence.
static func sentence_case(text: String) -> String:
	if text.is_empty():
		return text
	return text[0].to_upper() + text.substr(1)


## Index of a filler not in `used`, or -1 when every filler has been used.
static func pick_filler(rng: SimRng, used: Array) -> int:
	var free: Array[int] = []
	for i in FILLERS.size():
		if not (i in used):
			free.append(i)
	if free.is_empty():
		return -1
	return free[rng.below(free.size())]


static func filler_headline(index: int, values: Dictionary) -> String:
	return fill(String(FILLERS[index]["headline"]), values, true)


static func filler_body(index: int, values: Dictionary) -> String:
	return fill(String(FILLERS[index]["body"]), values)


static func _grouped(n: int) -> String:
	var negative := n < 0
	var digits := str(absi(n))
	var out := ""
	var i := digits.length()
	while i > 3:
		out = "," + digits.substr(i - 3, 3) + out
		i -= 3
	out = digits.substr(0, i) + out
	return ("-" + out) if negative else out
