-- Radio call flavour for Desert Air Patrol. All names and stories are fiction.
local calls = {}

calls.medevac = {
  {who = "Earl", variant = 4, story = "Earl fell off a windmill he was fixing and can't put weight on his ankle.",
   thanks = "Earl's ankle is in good hands now. He wants you to know the windmill is fine."},
  {who = "Rosa", variant = 9, story = "Rosa fainted in the heat outside a car lot. Bystanders have her in the shade.",
   thanks = "Rosa is sipping water and complaining about the hospital gown. That's a good sign."},
  {who = "Marty", variant = 2, story = "Marty tried to juggle cactus pears for tourists. It went about how you'd think.",
   thanks = "The nurses have tweezers and patience. Marty is going to be just fine."},
  {who = "Dolly", variant = 11, story = "Dolly was stung by a whole swarm of bees at the farmers' market.",
   thanks = "Dolly is swelling down nicely and already planning to sue the bees."},
  {who = "Gus", variant = 6, story = "Gus is a showgirl's stagehand who caught a falling spotlight. With his head.",
   thanks = "Gus has a mild concussion and a great story for the break room."}
}

calls.hikers = {
  {who = "Wanda", variant = 13, story = "Wanda went out to photograph a sunset and lost track of her car.",
   thanks = "Wanda got her sunset photos, a little sunburn and a ride home. Not a bad day."},
  {who = "Pete", variant = 5, story = "Pete followed a roadrunner \"just a little way\" and is now very lost.",
   thanks = "Pete swears the roadrunner was laughing at him. The doctor says he's just dehydrated."},
  {who = "the Hendersons' boy", variant = 1, story = "The Hendersons' boy wandered off from a church picnic.",
   thanks = "The Hendersons' boy is getting a juice box and a talking-to. Nice flying."}
}

calls.suspects = {
  {kind = "sedan", what = "a sedan", crime = "A man in a gold lamé jacket just walked out of a casino cage with a sack of chips."},
  {kind = "compact", what = "a compact", crime = "Someone swiped the neon cowboy's hat off the Lucky Spur sign. Again."},
  {kind = "pickup", what = "a pickup", crime = "A pickup full of stolen slot machines is trying to leave town."},
  {kind = "taxi", what = "a taxi", crime = "A fake cabbie has been taking tourists the long way. Very, very long."},
  {kind = "sedan", what = "a sedan", crime = "An Elvis impersonator robbed a wedding chapel. Thank you very much."}
}

calls.officers = {"Officer Tran", "Sergeant Mbeki", "Deputy Lund", "Officer Castellanos"}

calls.traffic_lines = {
  function(count) return "\"" .. count .. " cars crawling along down there, folks. Take the back way.\"" end,
  function(count) return "\"I can see " .. count .. " vehicles and one very patient tumbleweed.\"" end,
  function(count) return "\"" .. count .. " cars, zero hurry. Somebody's mother-in-law is visiting.\"" end,
  function(count) return "\"From up here it's " .. count .. " cars and a whole lot of honking.\"" end,
  function(count)
    if count == 0 then return "\"Wide open down here. Not a soul. Enjoy it while it lasts.\"" end
    return "\"Only " .. count .. " cars here. Practically a ghost town.\""
  end
}

calls.charters = {
  {who = "Mr. Silverman", variant = 8, rule = "hurry", ask = "a casino owner late for a board meeting",
   dest = "Board meeting", thanks = "Mr. Silverman tips like a man who just bought a hotel.",
   late = "Mr. Silverman missed the vote. He tips like a man who just lost a hotel."},
  {who = "Bunny LaRue", variant = 12, rule = "nervous", ask = "a lounge singer who hates flying",
   dest = "Bunny's matinee", thanks = "Bunny says it was the smoothest flight of her life. She might even fly again.",
   late = "Bunny has your name on a list now. Not a good list."},
  {who = "Professor Okoye", variant = 3, rule = nil, ask = "a geologist who wants to see the town from above",
   dest = "Survey site", thanks = "The professor took three hundred photos. You're in about forty of them."},
  {who = "the Fontaine twins", variant = 10, rule = "hurry", ask = "two magicians about to be late for their own show",
   dest = "Stage door", thanks = "The twins made your tip appear out of thin air. Then made it double.",
   late = "The twins made your tip disappear. That's their best trick."},
  {who = "Grandma Pearl", variant = 14, rule = "nervous", ask = "a grandmother on her first helicopter ride",
   dest = "Pearl's bridge club", thanks = "Grandma Pearl says you fly better than her late husband drove.",
   late = "Grandma Pearl clutched her pocketbook the whole way. She'll take the bus next time."}
}

return calls
