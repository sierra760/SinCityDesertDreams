-- Job flavour for Silver State Express. All names and businesses are fiction.
local jobs = {}

jobs.rush = {
  {item = "a briefcase of signed contracts", from = "Hollis & Bray, attorneys", sender = 8, to = "Judge Amaral's chambers", recipient = 3,
   thanks = "Judge Amaral checks the signatures, nods once and stamps it. That's a yes from the bench."},
  {item = "the only key to the Starlite vault", from = "Starlite Hotel front desk", sender = 2, to = "the vault technician", recipient = 6,
   thanks = "The technician lets out a long breath. \"You have no idea how much money is behind that door.\""},
  {item = "a show reel for an audition", from = "Velvet Rope Talent", sender = 12, to = "the casting office", recipient = 9,
   thanks = "The casting director slides the reel in with seconds to spare. The talent agent owes you one."},
  {item = "replacement dice for the craps tables", from = "Lucky Seven Supply", sender = 4, to = "the pit boss", recipient = 1,
   thanks = "The pit boss rolls them twice and grins. \"Perfectly balanced. Like a good courier.\""}
}

jobs.milk = {
  {item = "fresh flowers", to = "Mrs. Albescu", variant = 11, thanks = "Mrs. Albescu puts them straight in water and tells you you're a dear."},
  {item = "a box of horseshoes", to = "the blacksmith", variant = 5, thanks = "The blacksmith tips his hat. \"Lucky for me, lucky for you.\""},
  {item = "a stack of racing forms", to = "Lefty", variant = 2, thanks = "Lefty already has a pencil behind his ear. \"Third race, trust me.\""},
  {item = "a crate of maraschino cherries", to = "the Sundowner bar", variant = 7, thanks = "The bartender salutes you with a cherry on a toothpick."},
  {item = "a guitar string set", to = "a busker", variant = 13, thanks = "The busker restrings on the spot and plays you a thank-you chord."},
  {item = "six dozen eggs", to = "the Twin Pines diner", variant = 10, thanks = "The cook counts all seventy-two. Not one cracked. Impressive."},
  {item = "a new sequined cape", to = "a showgirl", variant = 14, thanks = "She twirls it once on the sidewalk. Traffic slows down to look."},
  {item = "tax forms", to = "Mr. Pruitt", variant = 4, thanks = "Mr. Pruitt sighs. \"Thank you. I suppose.\""}
}

jobs.ice = {
  {from = "Polar Bear Ice House", sender = 6, to = "the Lucky Spur ice sculptor", recipient = 12,
   thanks = "The sculptor starts carving a swan before the tailgate is even down."},
  {from = "Frosty's Ice Works", sender = 3, to = "the Desert Rose pool party", recipient = 9,
   thanks = "The pool party cheers. Someone hands you a lemonade with your own ice in it."},
  {from = "North Pole Packing", sender = 5, to = "the fish market", recipient = 1,
   thanks = "The fishmonger shovels it straight onto the catch of the day."}
}

jobs.cake = {
  {from = "Bellissima Bakery", sender = 10, to = "the Chapel of Neon Love", recipient = 11, couple = "Frankie and Dot",
   thanks = "Frankie and Dot cut the cake together. Somebody's uncle is already crying."},
  {from = "Sugar & Sage", sender = 13, to = "the Silver Bells Wedding Chapel", recipient = 8, couple = "Ramona and Lee",
   thanks = "Ramona and Lee feed each other the first slice. Lee misses. Everyone laughs."},
  {from = "Golden Crumb Patisserie", sender = 14, to = "the Little Desert Chapel", recipient = 0, couple = "Gil and Marguerite",
   thanks = "Gil and Marguerite have been married fifty years today. They say the cake is even better than the first one."}
}

return jobs
