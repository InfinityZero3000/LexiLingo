"""IELTS Academic Practice Test 1 — a full-length paper.

Written to the real exam's shape, because a short paper cannot report a band:
the conversion tables are defined on 40 questions and `_band_from_table` scales
a shorter section up to that equivalent, so five correct answers out of five
would report band 9.

    Listening  4 parts, 40 questions, 30 minutes, each recording played once
    Reading    3 passages, 40 questions, 60 minutes, no extra transfer time
    Writing    Task 1 (150 words, ~20 min) + Task 2 (250 words, ~40 min)
    Speaking   Part 1 interview, Part 2 cue card (1 min prep / 2 min talk),
               Part 3 discussion

Every Listening part carries its `transcript`. The transcript is what makes the
answers checkable by a human, and it is also the input a text-to-speech pass
needs to produce the recording — `audio_url` is empty until one exists, and the
admin validator refuses to publish a Listening part without it.

Answer keys use the exam's own tolerances: `accepted_answers` lists the variants
that score, because "52 Wilton Road" and "Wilton Road" are both what a candidate
writes on the answer sheet depending on how the gap is printed.
"""

LISTENING_PART_1_TRANSCRIPT = """
RECEPTIONIST: Good morning, Riverside Community Centre, Tom speaking.
WOMAN: Oh, hello. I'd like to ask about family membership, please.
RECEPTIONIST: Of course. Can I take your name?
WOMAN: Yes, it's Helen Brannigan.
RECEPTIONIST: Could you spell the surname for me?
WOMAN: B-R-A-N-N-I-G-A-N.
RECEPTIONIST: Brannigan, lovely. And your address?
WOMAN: We're at number 52 Wilton Road. That's W-I-L-T-O-N.
RECEPTIONIST: Is that Wilton Road in Ashcombe?
WOMAN: That's right, though the post always seems to end up in Wilton Street,
which is the next one along.
RECEPTIONIST: I'll make a note. Now, we have two family memberships. The full
one gives you access at any time and that's 62 pounds a month. The off-peak is
cheaper, but you can't use the centre between five and eight in the evening.
WOMAN: Weekday evenings are when my husband would want to swim, so — actually,
no. He works late anyway. Let's take the off-peak one.
RECEPTIONIST: Off-peak it is. That's 46 pounds a month.
WOMAN: I thought it was 40.
RECEPTIONIST: It was until January, I'm afraid. It went up to 46.
WOMAN: Fine. And when could we start?
RECEPTIONIST: Memberships begin on the first of the month, so the first of
April — or, if you'd like to start sooner, we can do the third of March, this
Friday, for a part-month payment.
WOMAN: The third of March, then. My daughter wants to start straight away.
RECEPTIONIST: What's she interested in?
WOMAN: She's been asking about gymnastics for a year, but the class is full, so
she'll do swimming with her brother.
RECEPTIONIST: Swimming, right. Both children on the swimming programme. Now,
every new family comes in for an induction. We run those on Tuesdays and
Thursdays. Tuesday's group is full this week.
WOMAN: Thursday, then.
RECEPTIONIST: Thursday at 6.30. It lasts about forty minutes.
WOMAN: Is there anything we need to bring?
RECEPTIONIST: Just photo ID for the adults — a driving licence or a passport.
You don't need to bring the children's, and the swimming kit can wait until
after the tour.
""".strip()

LISTENING_PART_2_TRANSCRIPT = """
GUIDE: Good afternoon everyone, and welcome to Ashcombe City Farm. Before we
start the tour, a few practical things.
The farm is open every day except Monday, when the animals are moved to the
back field and the site closes for maintenance. Entry is free, though we do ask
for a donation at the gate — most visitors give two or three pounds, and that
money goes entirely on animal feed.
Now, the site. If you're standing at the entrance with the car park behind you,
the Barn is the long brick building directly ahead. That's the oldest structure
here — it dates from 1846 — and it was completely rebuilt three years ago after
a fire in the roof space. Nobody was hurt, but we lost the original beams.
To the left of the Barn is the Orchard. We have forty-two apple trees, all of
them local varieties that were nearly lost, and in October we press the fruit
into juice which we sell in the shop.
Beyond the Orchard is the Pond. It's fenced, so children can only go in with an
adult, and it's the one part of the farm where we ask you not to feed anything
— the ducks are already overfed by half of Ashcombe.
On the right-hand side you'll find the Greenhouse. That's run entirely by
volunteers, about thirty of them, and everything grown there goes to the
community kitchen rather than the shop.
Next to the Greenhouse is the Workshop, where we repair tools and machinery.
It's not open to the public during the week, but on Saturday mornings we run
free repair sessions — bring a broken chair or a bicycle and someone will show
you how to mend it.
Finally, the Café. It's in the small white building by the gate. It only opens
at weekends at the moment because we can't staff it, and it's the only place on
site where you can pay by card. Everywhere else is cash only.
""".strip()

LISTENING_PART_3_TRANSCRIPT = """
TUTOR: Right, Ravi, Ellen — how's the noise pollution project going?
ELLEN: Better than we expected. We've finished the measurements.
TUTOR: Where did you take them in the end?
RAVI: We'd planned to do the main road and the park, but the park was so quiet
that the readings were meaningless — everything sat at the bottom of the scale.
So we swapped it for the station forecourt.
TUTOR: Good decision. The contrast matters more than the coverage.
ELLEN: The surprising thing was the time of day. We assumed the peak would be
the morning rush, but the loudest hour at both sites was between eleven and
midnight — the pubs emptying, mostly, plus deliveries.
TUTOR: That's consistent with the literature, actually. What about the survey?
RAVI: We got 210 responses, which is more than we needed. The problem is that
most of them came from the university mailing list, so the sample is almost
entirely people under twenty-five.
TUTOR: So what will you do about that?
ELLEN: We're not going to collect more. We'll report it as a limitation and be
explicit that the findings apply to a student population.
TUTOR: I'd rather you did that than pretend the sample is representative. Now,
the write-up. Who's doing what?
RAVI: I'll do the literature review — I've read most of it already.
ELLEN: And I'll write up the methodology, because I designed the survey.
TUTOR: What about the statistics?
ELLEN: Neither of us is confident with the regression, so we've asked Priya
from the statistics department to check our analysis before we submit.
TUTOR: Sensible. And the conclusion?
RAVI: We'll write that together in the last week.
TUTOR: Make sure you leave time. Every group underestimates the conclusion.
One more thing — the deadline moved. It's now the fourteenth, not the
twenty-first, because the marking window changed.
ELLEN: The fourteenth. That's a week earlier.
TUTOR: It is. I'd start the write-up now rather than after the reading week.
""".strip()

LISTENING_PART_4_TRANSCRIPT = """
LECTURER: Today I want to look at desalination — turning seawater into drinking
water — and at why a technology that sounds like an obvious solution to water
scarcity has spread so unevenly.
The oldest method is distillation: you boil seawater and condense the steam.
Sailors were doing this in the sixteenth century, and the first large municipal
plants, built in the 1950s, worked the same way. The drawback is energy. Boiling
water is expensive, and those early plants were only viable in places where fuel
was cheap, which is why the Gulf states dominated the industry for thirty years.
The change came with membranes. In reverse osmosis, seawater is forced under
pressure through a membrane whose pores are too small for salt to pass. The
principle was demonstrated in the 1950s at the University of California, but the
first commercial plant did not open until 1965. Reverse osmosis uses roughly a
quarter of the energy of distillation, and today it accounts for about seventy
per cent of global capacity.
That still leaves three problems. The first is energy: even at a quarter of the
cost, desalination remains the most energy-intensive way to supply water, and in
most countries the electricity comes from fossil fuels. The second is brine —
the concentrated salt left behind. A typical plant produces about 1.5 litres of
brine for every litre of fresh water, and when it is discharged into shallow
coastal water it sinks, because it is denser, and kills the seabed community
beneath the outfall.
The third problem is the one people forget: cost is dominated not by the plant
but by distribution. Moving water inland and uphill can cost more than producing
it, which is why desalination is concentrated in coastal cities and has been of
almost no use to the dry interiors that need it most.
There are partial answers. Pairing plants with solar power addresses the first
problem, and Australia now runs several plants on contracted renewable
electricity. For brine, the most promising route is recovery: magnesium and
bromine can both be extracted commercially, turning a waste stream into a
product. Neither answer is cheap, and both are easier to build into a new plant
than to add to an old one.
""".strip()


def _listening_section() -> dict:
    return {
        "skill": "listening",
        "duration_minutes": 30,
        "parts": [
            {
                "order": 1,
                "part_key": "listening_part_1",
                "title": "Part 1 — Riverside Community Centre membership",
                "audio_url": "",
                "transcript": LISTENING_PART_1_TRANSCRIPT,
                "instructions": (
                    "Questions 1-10. Complete the form below. Write NO MORE THAN "
                    "TWO WORDS AND/OR A NUMBER for each answer."
                ),
                "question_groups": [
                    {
                        "question_type": "form_completion",
                        "instructions": "MEMBERSHIP ENQUIRY FORM",
                        "questions": [
                            {"key": "L1", "number": 1, "prompt": "Surname:",
                             "accepted_answers": ["Brannigan"]},
                            {"key": "L2", "number": 2, "prompt": "Street:",
                             "accepted_answers": ["Wilton Road", "Wilton Rd"]},
                            {"key": "L3", "number": 3, "prompt": "House number:",
                             "accepted_answers": ["52"]},
                            {"key": "L4", "number": 4, "prompt": "Membership type:",
                             "accepted_answers": ["off-peak", "off peak"]},
                            {"key": "L5", "number": 5,
                             "prompt": "Monthly fee: £", "accepted_answers": ["46"]},
                            {"key": "L6", "number": 6, "prompt": "Start date:",
                             "accepted_answers": ["3 March", "March 3", "3rd March"]},
                            {"key": "L7", "number": 7,
                             "prompt": "Activity for both children:",
                             "accepted_answers": ["swimming"]},
                            {"key": "L8", "number": 8, "prompt": "Induction day:",
                             "accepted_answers": ["Thursday"]},
                            {"key": "L9", "number": 9, "prompt": "Induction time:",
                             "accepted_answers": ["6.30", "6:30", "6.30 pm", "18.30"]},
                            {"key": "L10", "number": 10, "prompt": "Adults must bring:",
                             "accepted_answers": ["photo ID", "photo identification"]},
                        ],
                    }
                ],
            },
            {
                "order": 2,
                "part_key": "listening_part_2",
                "title": "Part 2 — Ashcombe City Farm tour",
                "audio_url": "",
                "transcript": LISTENING_PART_2_TRANSCRIPT,
                "instructions": "Questions 11-20.",
                "question_groups": [
                    {
                        "question_type": "multiple_choice",
                        "instructions": "Questions 11-14. Choose the correct answer.",
                        "questions": [
                            {"key": "L11", "number": 11,
                             "prompt": "The farm is closed on Mondays because",
                             "options": [
                                 "the animals are moved and the site is maintained",
                                 "there are too few visitors to open",
                                 "the volunteers are not available",
                             ],
                             "accepted_answers": [
                                 "the animals are moved and the site is maintained"]},
                            {"key": "L12", "number": 12,
                             "prompt": "Money collected at the gate is spent entirely on",
                             "options": ["animal feed", "building repairs", "new equipment"],
                             "accepted_answers": ["animal feed"]},
                            {"key": "L13", "number": 13,
                             "prompt": "What does the guide say about the apple trees?",
                             "options": [
                                 "They are local varieties that were nearly lost.",
                                 "They were planted when the farm opened.",
                                 "They produce fruit that is given away free.",
                             ],
                             "accepted_answers": [
                                 "They are local varieties that were nearly lost."]},
                            {"key": "L14", "number": 14,
                             "prompt": "At the Pond, visitors are asked not to",
                             "options": ["feed the birds", "take photographs", "walk dogs"],
                             "accepted_answers": ["feed the birds"]},
                        ],
                    },
                    {
                        "question_type": "matching",
                        "instructions": (
                            "Questions 15-20. Which statement applies to each part of "
                            "the farm? Choose ONE answer for each."
                        ),
                        "questions": [
                            {"key": "L15", "number": 15, "prompt": "The Barn",
                             "options": [
                                 "It was rebuilt after a fire.",
                                 "It is staffed only by volunteers.",
                                 "It opens at weekends only.",
                                 "It may not be entered without an adult.",
                                 "It is closed to the public on weekdays.",
                                 "Its produce goes to the community kitchen.",
                             ],
                             "accepted_answers": ["It was rebuilt after a fire."]},
                            {"key": "L16", "number": 16, "prompt": "The Pond",
                             "options": [
                                 "It was rebuilt after a fire.",
                                 "It is staffed only by volunteers.",
                                 "It opens at weekends only.",
                                 "It may not be entered without an adult.",
                                 "It is closed to the public on weekdays.",
                                 "Its produce goes to the community kitchen.",
                             ],
                             "accepted_answers": ["It may not be entered without an adult."]},
                            {"key": "L17", "number": 17, "prompt": "The Greenhouse",
                             "options": [
                                 "It was rebuilt after a fire.",
                                 "It is staffed only by volunteers.",
                                 "It opens at weekends only.",
                                 "It may not be entered without an adult.",
                                 "It is closed to the public on weekdays.",
                                 "Its produce goes to the community kitchen.",
                             ],
                             "accepted_answers": ["It is staffed only by volunteers."]},
                            {"key": "L18", "number": 18, "prompt": "The Workshop",
                             "options": [
                                 "It was rebuilt after a fire.",
                                 "It is staffed only by volunteers.",
                                 "It opens at weekends only.",
                                 "It may not be entered without an adult.",
                                 "It is closed to the public on weekdays.",
                                 "Its produce goes to the community kitchen.",
                             ],
                             "accepted_answers": ["It is closed to the public on weekdays."]},
                            {"key": "L19", "number": 19, "prompt": "The Café",
                             "options": [
                                 "It was rebuilt after a fire.",
                                 "It is staffed only by volunteers.",
                                 "It opens at weekends only.",
                                 "It may not be entered without an adult.",
                                 "It is closed to the public on weekdays.",
                                 "Its produce goes to the community kitchen.",
                             ],
                             "accepted_answers": ["It opens at weekends only."]},
                            {"key": "L20", "number": 20,
                             "prompt": "Where can visitors pay by card?",
                             "options": ["the Café", "the shop", "the gate", "nowhere on site"],
                             "accepted_answers": ["the Café"]},
                        ],
                    },
                ],
            },
            {
                "order": 3,
                "part_key": "listening_part_3",
                "title": "Part 3 — Tutorial on a noise pollution project",
                "audio_url": "",
                "transcript": LISTENING_PART_3_TRANSCRIPT,
                "instructions": "Questions 21-30.",
                "question_groups": [
                    {
                        "question_type": "multiple_choice",
                        "instructions": "Questions 21-26. Choose the correct answer.",
                        "questions": [
                            {"key": "L21", "number": 21,
                             "prompt": "Why did the students change one of their sites?",
                             "options": [
                                 "The readings there were too low to be useful.",
                                 "They were refused permission to record.",
                                 "The equipment failed on the first visit.",
                             ],
                             "accepted_answers": [
                                 "The readings there were too low to be useful."]},
                            {"key": "L22", "number": 22,
                             "prompt": "Which site replaced it?",
                             "options": ["the station forecourt", "the shopping centre",
                                         "the bus depot"],
                             "accepted_answers": ["the station forecourt"]},
                            {"key": "L23", "number": 23,
                             "prompt": "The loudest hour at both sites was",
                             "options": ["late at night", "the morning rush hour",
                                         "the middle of the afternoon"],
                             "accepted_answers": ["late at night"]},
                            {"key": "L24", "number": 24,
                             "prompt": "What is the main weakness of the survey?",
                             "options": [
                                 "Almost all respondents are students.",
                                 "There were too few responses.",
                                 "The questions were ambiguous.",
                             ],
                             "accepted_answers": ["Almost all respondents are students."]},
                            {"key": "L25", "number": 25,
                             "prompt": "How will the students deal with that weakness?",
                             "options": [
                                 "They will report it as a limitation.",
                                 "They will collect a second sample.",
                                 "They will weight the results statistically.",
                             ],
                             "accepted_answers": ["They will report it as a limitation."]},
                            {"key": "L26", "number": 26,
                             "prompt": "The tutor's advice about the deadline is to",
                             "options": [
                                 "begin writing before the reading week",
                                 "ask for an extension",
                                 "submit the analysis separately",
                             ],
                             "accepted_answers": ["begin writing before the reading week"]},
                        ],
                    },
                    {
                        "question_type": "matching",
                        "instructions": (
                            "Questions 27-30. Who will do each task? Choose ONE answer "
                            "for each."
                        ),
                        "questions": [
                            {"key": "L27", "number": 27, "prompt": "the literature review",
                             "options": ["Ravi", "Ellen", "both students", "Priya"],
                             "accepted_answers": ["Ravi"]},
                            {"key": "L28", "number": 28, "prompt": "the methodology section",
                             "options": ["Ravi", "Ellen", "both students", "Priya"],
                             "accepted_answers": ["Ellen"]},
                            {"key": "L29", "number": 29, "prompt": "checking the analysis",
                             "options": ["Ravi", "Ellen", "both students", "Priya"],
                             "accepted_answers": ["Priya"]},
                            {"key": "L30", "number": 30, "prompt": "the conclusion",
                             "options": ["Ravi", "Ellen", "both students", "Priya"],
                             "accepted_answers": ["both students"]},
                        ],
                    },
                ],
            },
            {
                "order": 4,
                "part_key": "listening_part_4",
                "title": "Part 4 — Lecture: desalination",
                "audio_url": "",
                "transcript": LISTENING_PART_4_TRANSCRIPT,
                "instructions": (
                    "Questions 31-40. Complete the notes below. Write NO MORE THAN "
                    "TWO WORDS AND/OR A NUMBER for each answer."
                ),
                "question_groups": [
                    {
                        "question_type": "note_completion",
                        "instructions": "DESALINATION — LECTURE NOTES",
                        "questions": [
                            {"key": "L31", "number": 31,
                             "prompt": "Oldest method: ______, i.e. boiling and condensing",
                             "accepted_answers": ["distillation"]},
                            {"key": "L32", "number": 32,
                             "prompt": "First large municipal plants built in the ______",
                             "accepted_answers": ["1950s"]},
                            {"key": "L33", "number": 33,
                             "prompt": "Early plants only viable where ______ was cheap",
                             "accepted_answers": ["fuel"]},
                            {"key": "L34", "number": 34,
                             "prompt": "In reverse osmosis, salt cannot pass through the ______",
                             "accepted_answers": ["membrane"]},
                            {"key": "L35", "number": 35,
                             "prompt": "First commercial reverse osmosis plant opened in ______",
                             "accepted_answers": ["1965"]},
                            {"key": "L36", "number": 36,
                             "prompt": "Reverse osmosis now supplies about ______ per cent of world capacity",
                             "accepted_answers": ["70", "seventy"]},
                            {"key": "L37", "number": 37,
                             "prompt": "Waste product: ______, about 1.5 litres per litre of fresh water",
                             "accepted_answers": ["brine"]},
                            {"key": "L38", "number": 38,
                             "prompt": "Brine sinks and damages the ______ below the outfall",
                             "accepted_answers": ["seabed", "seabed community"]},
                            {"key": "L39", "number": 39,
                             "prompt": "Costs are dominated by ______ rather than by the plant",
                             "accepted_answers": ["distribution"]},
                            {"key": "L40", "number": 40,
                             "prompt": "Two chemicals worth recovering from brine: magnesium and ______",
                             "accepted_answers": ["bromine"]},
                        ],
                    }
                ],
            },
        ],
    }


READING_PASSAGE_1 = """
The Return of the Urban Beehive

Two decades ago, a hive on a city roof was an eccentricity. Today London,
Paris, Berlin and Melbourne all count their hives in the thousands, and the
waiting lists for beekeeping courses in each of those cities are longer than
the courses themselves. The revival began with alarm. Reports of colony losses
in commercial apiaries in the mid-2000s reached the public as a simple story —
the bees are dying — and city dwellers who had never kept an animal in their
lives responded by buying a hive.

The story was not quite right. What the reports described was a rise in the
mortality of managed honeybee colonies, a species that is farmed rather than
wild, and the global count of managed hives has in fact risen steadily since
1961. The species genuinely in trouble is not the honeybee but the several
hundred species of wild solitary bee, which do not live in hives, produce no
honey, and depend on undisturbed ground and dead wood for their nests. Almost
none of the enthusiasm of the last twenty years has been directed at them.

This matters because a honeybee colony is not a neutral addition to a city. A
single hive contains between twenty and sixty thousand foragers at its summer
peak, and those foragers collect from the same flowers that solitary bees
depend on. Where hive density is high, the competition is measurable.
Researchers in Paris found that the reproductive success of wild bees fell as
the number of hives within a kilometre rose, and a study in Montreal recorded
lower wild-bee diversity in exactly the neighbourhoods where urban beekeeping
was most popular. The honeybee, in other words, can behave in a city rather as
livestock behaves on grassland.

The competition is not inevitable. It appears where the density of hives
outruns the supply of flowers, and cities vary enormously in how much forage
they offer. A city of mown grass verges and ornamental evergreens supports very
few bees of any kind; a city of unmown road edges, allotments, cemeteries,
brownfield sites and gardens planted for pollen can support a great many. Berlin
and Ljubljana have both been able to raise hive numbers without a measurable
effect on wild populations, and both have unusually large areas of unmanaged
ground. Where London has run into difficulty, the constraint has been forage,
not hives.

Some cities have responded by regulating. Since 2019 several boroughs have
required new hives to be registered, and Oslo has gone further, refusing new
permits in districts where hive density already exceeds a threshold set by the
city's ecologists. Others have taken the opposite approach and put the money
into planting instead: Sheffield's road-verge programme, which replaced mowing
with wildflower sowing on more than a hundred kilometres of verge, cost less
than the city had previously spent on cutting the same grass.

The most effective interventions are also the least visible. A dead tree left
standing provides nesting cavities that no hive can substitute for. A patch of
bare, sun-warmed soil, the kind that tidy landscaping eliminates first,
supports the ground-nesting species that make up the majority of wild bees. Bee
hotels, the drilled wooden boxes sold in garden centres, help a narrow group of
cavity-nesting species and are frequently built in ways that spread disease
between occupants, but they have one undoubted merit: they make the invisible
visible, and a household that has watched a leafcutter bee seal a tube is more
likely to tolerate an untidy garden.

None of this makes urban beekeeping harmful in itself. A hive on a school roof
teaches more about pollination in a term than a textbook does in a year, and
city honey is a genuine product of a genuine landscape. The argument is about
proportion. A city that answers a pollinator crisis with hives has bought the
one solution that adds competitors rather than habitat; a city that answers it
with flowers has helped every species, including the one in the hive.
""".strip()

READING_PASSAGE_2 = """
Cooling the City

A. The temperature difference between a city and the countryside around it was
first measured in London in 1818 by Luke Howard, an amateur meteorologist who
noticed that his thermometer readings in the city ran consistently above those
taken outside it. He attributed the difference to the fuel burned in the city's
grates. He was partly right, but the larger cause turned out to be the fabric of
the city itself: brick, stone and asphalt absorb heat through the day and
release it slowly through the night, so the gap between city and country is
widest not at noon but a few hours before dawn.

B. The effect scales with size. A town of ten thousand people may run half a
degree warmer than its surroundings; a city of ten million can run eight degrees
warmer on a still, clear night. Wind erases the difference, and cloud reduces
it, which is why the heat island is at its most dangerous during exactly the
conditions that produce heatwaves. The people most exposed are those on upper
floors of buildings without ventilation, and the strongest single predictor of
heat mortality in European cities is not income but age.

C. The engineering response has, until recently, been mechanical. Air
conditioning removes heat from an interior and discharges it into the street,
which is to say it cools a building by warming the city. In Paris, one study
estimated that the collective heat discharged by air conditioning raised
street-level temperatures by up to two degrees during a heatwave, transferring
risk from those who own a unit to those who do not.

D. Surfaces offer a cheaper route. A conventional dark roof reaches seventy
degrees in summer sun; a white-painted one stays below forty-five. Repainting
roofs is one of the few climate interventions whose costs are small enough to
be met from a maintenance budget rather than a capital one, and Ahmedabad, in
India, has coated more than three thousand roofs in a programme aimed
explicitly at low-income housing. The measured drop in indoor temperature was
between two and five degrees.

E. Vegetation works differently and better. A tree does not merely shade the
ground beneath it; it moves water from the soil into the air, and the energy
that evaporation consumes is energy that does not heat the street. A mature
street tree has a cooling effect equivalent to several room-sized air
conditioners running continuously, at no cost in electricity. The catch is
water and time: the benefit arrives twenty years after the planting, and in a
drought the tree that cools the street is competing for the same supply as the
people on it.

F. Water itself has been rediscovered. Seville has revived a Moorish technique
of narrow shaded alleys with running water at their base, and Zurich has
uncovered streams that were culverted in the nineteenth century. Both projects
were justified on amenity grounds and defended, once built, on thermal ones.

G. What none of these measures does is address the underlying driver, and this
is the point at which municipal ambition usually stops. Heat islands are made
worse by climate change but they are not caused by it; they are caused by the
way cities are built, and the surfaces that create them are replaced on a
cycle of decades. A city that decided today to require reflective roofs, deep
street trees and permeable ground on every new development would still be a
hot city in 2060 — but a measurably cooler one than the city it would otherwise
have become.
""".strip()

READING_PASSAGE_3 = """
The Measurement of Happiness

For most of the twentieth century, economists treated wellbeing as something
that could be inferred rather than asked about. If people chose one job over
another, or one country over another, their choices revealed their preferences,
and preferences were as close to happiness as a science needed to get. Income
served as the proxy, and for a long time the proxy behaved. Richer countries
reported more satisfaction with life than poorer ones; within any one country,
richer people reported more satisfaction than poorer ones.

Then, in 1974, the economist Richard Easterlin noticed something that did not
fit. Although rich people within a country were more satisfied than poor
people, and rich countries more satisfied than poor countries, the average
satisfaction of a country did not seem to rise as that country grew richer over
time. Japan's real income multiplied several times between the 1950s and the
1980s without any corresponding movement in reported satisfaction. The
observation became known as the Easterlin paradox, and the argument about it
has run for fifty years.

The explanations divide into two families. The first is relative income: what
raises satisfaction is not what one has but what one has compared with one's
neighbours, and growth that lifts everyone leaves the comparison unchanged. The
second is adaptation: people adjust to improvements, so a gain that feels
substantial in the year it arrives has been absorbed into the baseline within
three or four years. Both effects are real and both are measurable. Neither
fully explains the paradox, and a more recent generation of studies using
larger datasets has found that satisfaction does rise with national income
after all, though far more slowly than income itself — the relationship is
roughly logarithmic, so doubling income moves satisfaction by a constant and
rather small amount whether the doubling starts from two thousand dollars or
from sixty thousand.

Part of the difficulty is that the question is doing more work than it can
carry. "How satisfied are you with your life these days, on a scale of nought
to ten?" asks for an evaluation, a judgement made in the moment about a whole
life. A different question — "how did you feel yesterday?" — asks for
experience, and the two produce different answers and correlate with different
things. Evaluation tracks income, education and status. Experience tracks
sleep, pain, social contact and time pressure, and stops responding to income
at a far lower threshold. A person can rate their life highly on Monday and
report a miserable Sunday without contradiction.

Governments that have adopted wellbeing measures have generally adopted the
evaluative version, because it is stable, comparable across countries and easy
to put in a table. Bhutan's Gross National Happiness index, established in
2008, is the most cited example, though it is not in fact a satisfaction
measure at all: it is a composite of nine domains including health, education
and ecological diversity, closer to a development index than to a survey of
mood. New Zealand's wellbeing budget of 2019 went further in one respect, in
that it changed how money was allocated rather than merely how outcomes were
reported.

The objections are serious. A number derived from a survey is a weak
instrument for allocating a national budget, and any measure that governments
are judged by will eventually be managed rather than measured. There is also
the problem of adaptation cutting the other way: people in persistently bad
conditions often report higher satisfaction than an observer would predict,
because they have adjusted their expectations, and a policy that follows the
survey would direct less help precisely where deprivation has lasted longest.

None of this is an argument for going back to income. It is an argument for
holding several numbers at once — income, life evaluation, daily experience,
and the distribution of each — and for being explicit about which question each
one answers. The measurement of happiness has not failed. What has failed is
the hope that a single number could stand in for a life.
""".strip()


def _q(key, number, prompt, answers, options=None):
    question = {"key": key, "number": number, "prompt": prompt,
                "accepted_answers": answers}
    if options:
        question["options"] = options
    return question


# TRUE/FALSE/NOT GIVEN and YES/NO/NOT GIVEN carry their options in the question
# type, the way the exam prints them — the client supplies the three choices.
_HEADINGS = [
    "i. A discovery and its true cause",
    "ii. Why size makes the problem worse",
    "iii. Cooling one building at the expense of the street",
    "iv. A cheap change of colour",
    "v. The slow but superior option",
    "vi. An old technology rediscovered",
    "vii. The limit of municipal ambition",
    "viii. Measuring temperature from orbit",
    "ix. Designing streets around the wind",
]


def _reading_section() -> dict:
    return {
        "skill": "reading",
        "duration_minutes": 60,
        "parts": [
            {
                "order": 1,
                "part_key": "reading_passage_1",
                "title": "Passage 1 — The Return of the Urban Beehive",
                "passage_title": "The Return of the Urban Beehive",
                "passage_text": READING_PASSAGE_1,
                "instructions": (
                    "Questions 1-13. You should spend about 20 minutes on this passage."
                ),
                "question_groups": [
                    {
                        "question_type": "true_false_notgiven",
                        "instructions": (
                            "Questions 1-6. Do the following statements agree with the "
                            "information in the passage? Write TRUE, FALSE or NOT GIVEN."
                        ),
                        "questions": [
                            _q("R1", 1, "Beekeeping courses in the cities named have more "
                               "applicants than they can take.", ["TRUE"]),
                            _q("R2", 2, "The number of managed honeybee hives worldwide has "
                               "fallen since 1961.", ["FALSE"]),
                            _q("R3", 3, "Solitary bees produce less honey than honeybees.",
                               ["FALSE"]),
                            _q("R4", 4, "The Paris and Montreal studies used the same "
                               "research methods.", ["NOT GIVEN"]),
                            _q("R5", 5, "A honeybee colony may contain as many as sixty "
                               "thousand foragers in summer.", ["TRUE"]),
                            _q("R6", 6, "Berlin has increased its hive numbers without a "
                               "measurable effect on wild bees.", ["TRUE"]),
                        ],
                    },
                    {
                        "question_type": "sentence_completion",
                        "instructions": (
                            "Questions 7-10. Complete the sentences. Write NO MORE THAN "
                            "TWO WORDS from the passage for each answer."
                        ),
                        "questions": [
                            _q("R7", 7, "Competition appears where the density of hives "
                               "outruns the supply of ______.", ["flowers"]),
                            _q("R8", 8, "Oslo refuses new permits once hive density passes "
                               "a threshold set by the city's ______.", ["ecologists"]),
                            _q("R9", 9, "Sheffield replaced mowing with wildflower ______ "
                               "on over a hundred kilometres of verge.", ["sowing"]),
                            _q("R10", 10, "The majority of wild bee species nest in the "
                               "______.", ["ground"]),
                        ],
                    },
                    {
                        "question_type": "short_answer",
                        "instructions": (
                            "Questions 11-13. Answer the questions. Write NO MORE THAN "
                            "THREE WORDS from the passage for each answer."
                        ),
                        "questions": [
                            _q("R11", 11, "What do bee hotels frequently spread between "
                               "their occupants?", ["disease"]),
                            _q("R12", 12, "What does a standing dead tree provide that a "
                               "hive cannot replace?", ["nesting cavities", "cavities"]),
                            _q("R13", 13, "According to the final paragraph, what should a "
                               "city offer instead of more hives?", ["flowers", "habitat"]),
                        ],
                    },
                ],
            },
            {
                "order": 2,
                "part_key": "reading_passage_2",
                "title": "Passage 2 — Cooling the City",
                "passage_title": "Cooling the City",
                "passage_text": READING_PASSAGE_2,
                "instructions": (
                    "Questions 14-26. You should spend about 20 minutes on this passage."
                ),
                "question_groups": [
                    {
                        "question_type": "matching_headings",
                        "instructions": (
                            "Questions 14-20. Choose the correct heading for each "
                            "paragraph from the list below."
                        ),
                        "questions": [
                            _q("R14", 14, "Paragraph A", [_HEADINGS[0]], _HEADINGS),
                            _q("R15", 15, "Paragraph B", [_HEADINGS[1]], _HEADINGS),
                            _q("R16", 16, "Paragraph C", [_HEADINGS[2]], _HEADINGS),
                            _q("R17", 17, "Paragraph D", [_HEADINGS[3]], _HEADINGS),
                            _q("R18", 18, "Paragraph E", [_HEADINGS[4]], _HEADINGS),
                            _q("R19", 19, "Paragraph F", [_HEADINGS[5]], _HEADINGS),
                            _q("R20", 20, "Paragraph G", [_HEADINGS[6]], _HEADINGS),
                        ],
                    },
                    {
                        "question_type": "sentence_completion",
                        "instructions": (
                            "Questions 21-23. Complete the sentences. Write NO MORE THAN "
                            "TWO WORDS AND/OR A NUMBER for each answer."
                        ),
                        "questions": [
                            _q("R21", 21, "The gap between city and country temperatures is "
                               "widest a few hours before ______.", ["dawn"]),
                            _q("R22", 22, "In European cities the strongest single predictor "
                               "of heat mortality is ______.", ["age"]),
                            _q("R23", 23, "Ahmedabad has coated more than ______ roofs.",
                               ["3000", "3,000", "three thousand"]),
                        ],
                    },
                    {
                        "question_type": "true_false_notgiven",
                        "instructions": (
                            "Questions 24-26. Write TRUE, FALSE or NOT GIVEN."
                        ),
                        "questions": [
                            _q("R24", 24, "Air conditioning was estimated to raise Paris "
                               "street temperatures by as much as two degrees during a "
                               "heatwave.", ["TRUE"]),
                            _q("R25", 25, "White roofs in Ahmedabad lowered indoor "
                               "temperatures by more than five degrees.", ["FALSE"]),
                            _q("R26", 26, "Zurich uncovered its streams primarily in order "
                               "to reduce street temperatures.", ["FALSE"]),
                        ],
                    },
                ],
            },
            {
                "order": 3,
                "part_key": "reading_passage_3",
                "title": "Passage 3 — The Measurement of Happiness",
                "passage_title": "The Measurement of Happiness",
                "passage_text": READING_PASSAGE_3,
                "instructions": (
                    "Questions 27-40. You should spend about 20 minutes on this passage."
                ),
                "question_groups": [
                    {
                        "question_type": "yes_no_notgiven",
                        "instructions": (
                            "Questions 27-31. Do the following statements agree with the "
                            "claims of the writer? Write YES, NO or NOT GIVEN."
                        ),
                        "questions": [
                            _q("R27", 27, "Economists once treated people's choices as "
                               "evidence of how happy they were.", ["YES"]),
                            _q("R28", 28, "The Easterlin paradox has now been resolved.",
                               ["NO"]),
                            _q("R29", 29, "Japan was the only country Easterlin examined.",
                               ["NOT GIVEN"]),
                            _q("R30", 30, "Life evaluation and daily experience respond to "
                               "the same factors.", ["NO"]),
                            _q("R31", 31, "Governments favour evaluative measures partly "
                               "because they are easy to tabulate.", ["YES"]),
                        ],
                    },
                    {
                        "question_type": "summary_completion",
                        "instructions": (
                            "Questions 32-36. Complete the summary. Write ONE WORD ONLY "
                            "from the passage for each answer."
                        ),
                        "questions": [
                            _q("R32", 32, "Larger datasets show satisfaction rising with "
                               "national income, but the relationship is ______, so each "
                               "doubling of income adds the same small amount.",
                               ["logarithmic"]),
                            _q("R33", 33, "One explanation of the paradox is ______ income, "
                               "which concerns comparison with one's neighbours.",
                               ["relative"]),
                            _q("R34", 34, "The other is ______, by which gains are absorbed "
                               "into the baseline within a few years.", ["adaptation"]),
                            _q("R35", 35, "Evaluative questions track income, education and "
                               "______.", ["status"]),
                            _q("R36", 36, "People in lasting deprivation may report high "
                               "satisfaction because they have adjusted their ______.",
                               ["expectations"]),
                        ],
                    },
                    {
                        "question_type": "multiple_choice",
                        "instructions": "Questions 37-40. Choose the correct answer.",
                        "questions": [
                            _q("R37", 37, "New Zealand's 2019 wellbeing budget differed from "
                               "other wellbeing measures because it",
                               ["changed how money was allocated"],
                               ["changed how money was allocated",
                                "used experiential rather than evaluative questions",
                                "combined nine separate domains",
                                "was the first to be published"]),
                            _q("R38", 38, "Experiential wellbeing stops responding to income",
                               ["at a lower level than life evaluation does"],
                               ["at a lower level than life evaluation does",
                                "at the same level as life evaluation",
                                "only in the richest countries",
                                "once basic needs are unmet"]),
                            _q("R39", 39, "Bhutan's Gross National Happiness index is best "
                               "described as",
                               ["a composite development index"],
                               ["a composite development index",
                                "a survey of daily mood",
                                "a measure of relative income",
                                "an experiential wellbeing measure"]),
                            _q("R40", 40, "The writer concludes that wellbeing should be "
                               "reported",
                               ["as several numbers answering different questions"],
                               ["as several numbers answering different questions",
                                "as a single national figure",
                                "by returning to income as the measure",
                                "only where survey samples are large"]),
                        ],
                    },
                ],
            },
        ],
    }


def _writing_section() -> dict:
    return {
        "skill": "writing",
        "duration_minutes": 60,
        "parts": [
            {
                "order": 1,
                "part_key": "writing_task_1",
                "title": "Task 1",
                # There is no image pipeline for charts yet, so the figures live
                # in the prompt. A candidate can still select, compare and report
                # — which is what Task 1 is assessed on — and `image_url` can be
                # filled in later without changing the task.
                "prompt": (
                    "The table below shows the number of visits (in millions) made to "
                    "four types of cultural venue in one European country in 2005, 2015 "
                    "and 2023.\n\n"
                    "                     2005     2015     2023\n"
                    "  Public libraries    92.4     71.8     48.5\n"
                    "  Museums             38.1     46.9     52.3\n"
                    "  Cinemas             61.0     58.2     33.7\n"
                    "  Live music venues   19.6     27.4     35.1\n\n"
                    "Summarise the information by selecting and reporting the main "
                    "features, and make comparisons where relevant.\n\n"
                    "Write at least 150 words."
                ),
                "min_words": 150,
                "suggested_minutes": 20,
                "image_url": "",
            },
            {
                "order": 2,
                "part_key": "writing_task_2",
                "title": "Task 2",
                "prompt": (
                    "Write about the following topic:\n\n"
                    "Some people believe that governments should spend public money on "
                    "preserving historic buildings, while others argue that this money "
                    "would be better spent on new housing and infrastructure.\n\n"
                    "Discuss both these views and give your own opinion.\n\n"
                    "Give reasons for your answer and include any relevant examples from "
                    "your own knowledge or experience.\n\n"
                    "Write at least 250 words."
                ),
                "min_words": 250,
                "suggested_minutes": 40,
            },
        ],
    }


def _speaking_section() -> dict:
    return {
        "skill": "speaking",
        "duration_minutes": 14,
        "parts": [
            {
                "order": 1,
                "part_key": "speaking_part_1",
                "title": "Part 1 — Introduction and interview (4-5 minutes)",
                "prompt": (
                    "Answer these questions as you would in the interview.\n\n"
                    "Your home town\n"
                    "1. Where is your home town, and how long have you lived there?\n"
                    "2. What do you like most about it?\n"
                    "3. Has it changed much since you were a child?\n\n"
                    "Free time\n"
                    "4. What do you usually do at the weekend?\n"
                    "5. Do you prefer spending free time alone or with other people? Why?\n\n"
                    "Technology\n"
                    "6. How often do you use a computer?\n"
                    "7. Is there any technology you would rather do without?"
                ),
                "prep_seconds": 0,
                "speak_seconds": 300,
            },
            {
                "order": 2,
                "part_key": "speaking_part_2",
                "title": "Part 2 — Individual long turn (3-4 minutes)",
                "cue_card": (
                    "Describe a place you have visited that made a strong impression "
                    "on you.\n\n"
                    "You should say:\n"
                    "  • where it is\n"
                    "  • when you went there and who you went with\n"
                    "  • what you did there\n"
                    "and explain why it made such a strong impression on you.\n\n"
                    "You will have one minute to prepare. You may make notes. "
                    "Then speak for one to two minutes."
                ),
                "prep_seconds": 60,
                "speak_seconds": 120,
            },
            {
                "order": 3,
                "part_key": "speaking_part_3",
                "title": "Part 3 — Two-way discussion (4-5 minutes)",
                "prompt": (
                    "Now let's talk more generally about travel and places.\n\n"
                    "1. Why do you think some places attract far more visitors than "
                    "others?\n"
                    "2. What effects can large numbers of tourists have on a small town?\n"
                    "3. Should governments limit the number of visitors to fragile sites? "
                    "Why or why not?\n"
                    "4. Do you think people travel for different reasons now than they did "
                    "fifty years ago?\n"
                    "5. How might travel change in the next twenty years?"
                ),
                "prep_seconds": 0,
                "speak_seconds": 300,
            },
        ],
    }


TITLE = "IELTS Academic Practice Test 1"
SLUG = "ielts-academic-practice-test-1"
DESCRIPTION = (
    "A full-length IELTS Academic practice test: 4 listening parts (40 questions), "
    "3 reading passages (40 questions), Writing Task 1 and Task 2, and a three-part "
    "Speaking interview. Listening and Reading are marked against the published band "
    "tables; Writing and Speaking are graded against the four band descriptors."
)

CONTENT = {
    "sections": [
        _listening_section(),
        _reading_section(),
        _writing_section(),
        _speaking_section(),
    ]
}
