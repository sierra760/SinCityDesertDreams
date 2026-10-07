# Secret codes

In a founded or loaded city, choose **Help → Secret Codes…**, or press
**Ctrl + Alt + Shift + C** (**Cmd + Option + Shift + C** on Mac). Type a code
and press Enter or Submit. Codes ignore case and surrounding whitespace.
Escape, the close button, and Never mind cancel without applying the code.
The city pauses while the form and feedback are open, then returns to its
previous speed. Explore suspends movement while they are open. If the keyboard
chord opened the form while Explore was running, Explore resumes by itself when
they close; opened from the Help menu, Explore waits for Resume, as after any
menu.

| Code | Effect |
| --- | --- |
| `DOUBLEDOWN` | Bets 10% of the treasury, at least $100 and at most $25,000. 47%: the stake doubles. 50%: the stake is lost. 3%: the tables catch fire and start a real firestorm; no money changes hands. If a firestorm roll finds nothing to burn, the stake is returned and the result says so. Refused when the treasury is below $100. |
| `HIGHROLLER` | $500,000, all inventions and gift permits. Place the gifts yourself. |
| `MARKER` | A real $25,000 bond at 20% yearly interest ($5,000/year), repayable in Budget. The ordinary outstanding-bond limit applies. |
| `CHAPEL` | The mayor marries the Budget at the Little Neon Chapel of the Desert. |

Each effect has exactly one code. The house keeps a 3-point edge on
DOUBLEDOWN, so repeated bets drift the treasury down rather than up.

Money, bonds, permits and invention dates use existing native-save fields.
HIGHROLLER preserves already standing gifts, existing military bases and
answered military proposals. An unoffered base uses the existing one-time
proposal and normal site/acceptance rules. No buildings are placed
automatically, and the city date and population do not jump. Resort
availability is immediate, but ordinary construction costs, utilities, growth
and launch rules still apply. DOUBLEDOWN rolls once on the saved simulation
RNG; a new military proposal also uses its normal RNG. Refused bets, gags,
unknown codes and markers do not draw RNG.

Implementation: the host opens the existing blocking NoticeDialog; Simulation
routes deliberate code redemption to `game/scripts/core/cheat_codes.gd`, which
also holds the betting odds, table limits and marker terms. The codes and
written lines live in `game/scripts/content/cheat_lines.gd`. RewardSystem
grants permits while preserving its ownership contract. Ordinary key shortcuts
do not interpret letter sequences as cheats.
