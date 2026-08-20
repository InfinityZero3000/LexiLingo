"""Seed one complete IELTS Academic mock paper.

Serves two purposes: it gives the app something real to sit, and it is the
reference an author copies in the admin editor. Idempotent by title.

    venv/bin/python3 scripts/seed_ielts_test.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.models.ielts import IeltsTest

TITLE = "IELTS Academic Practice Test 1"

READING_PASSAGE = """The Urban Heat Island Effect

Cities are consistently warmer than the countryside that surrounds them, a
phenomenon known as the urban heat island effect. On a still, clear night the
difference between a city centre and nearby farmland can exceed eight degrees
Celsius. The cause is not a single factor but an accumulation of them. Dark
surfaces such as asphalt and roofing absorb far more solar radiation than
vegetation does, and they release that heat slowly through the night. Tall
buildings trap radiation between their walls in what climatologists call an
urban canyon, and the same buildings block the wind that would otherwise carry
warm air away.

Vegetation cools a landscape mainly through evapotranspiration, the process by
which plants release water vapour. A mature tree can transpire hundreds of
litres on a hot day, and the energy consumed in evaporating that water is
energy that does not warm the air. Replacing a park with a car park therefore
removes a cooling system as well as adding a heat source. Waste heat from air
conditioning, vehicles and industry adds a further increment, one that grows
precisely when the city is already hottest.

The consequences reach beyond discomfort. Elevated night-time temperatures are
strongly associated with heat-related mortality, because the human body relies
on cooler nights to recover. Energy demand rises as air conditioners work
harder, which in most grids means burning more fuel and emitting more waste
heat, a feedback that reinforces the original problem. Some cities have
responded by mandating reflective roofing, which can lower surface temperatures
by tens of degrees, and by planting street trees, though the benefit of the
latter takes decades to mature and is often unevenly distributed: wealthier
districts are typically greener, and therefore cooler, than poorer ones."""

CONTENT = {
    "sections": [
        {
            "skill": "listening",
            "duration_minutes": 30,
            "parts": [
                {
                    "order": 1,
                    "title": "Part 1 — Community centre enquiry",
                    "audio_url": "/media/ielts/sample-part1.mp3",
                    "transcript": (
                        "WOMAN: Good morning, Riverside Community Centre. "
                        "MAN: Hello, I'd like to ask about the pottery class. "
                        "WOMAN: Certainly. It runs on Tuesday evenings, from seven "
                        "until nine. The fee is forty-five pounds for the term, and "
                        "you should bring an apron. The tutor is Helen Marsh."
                    ),
                    "instructions": (
                        "Complete the notes below. Write ONE WORD AND/OR A NUMBER "
                        "for each answer."
                    ),
                    "question_groups": [
                        {
                            "question_type": "note_completion",
                            "instructions": "Write ONE WORD AND/OR A NUMBER.",
                            "questions": [
                                {
                                    "key": "L1",
                                    "number": 1,
                                    "prompt": "The pottery class takes place on ______ evenings.",
                                    "accepted_answers": ["Tuesday"],
                                },
                                {
                                    "key": "L2",
                                    "number": 2,
                                    "prompt": "The class finishes at ______ o'clock.",
                                    "accepted_answers": ["nine", "9"],
                                },
                                {
                                    "key": "L3",
                                    "number": 3,
                                    "prompt": "The fee for the term is £______.",
                                    "accepted_answers": ["45", "forty-five"],
                                },
                                {
                                    "key": "L4",
                                    "number": 4,
                                    "prompt": "Students must bring an ______.",
                                    "accepted_answers": ["apron"],
                                },
                                {
                                    "key": "L5",
                                    "number": 5,
                                    "prompt": "The tutor's surname is ______.",
                                    "accepted_answers": ["Marsh"],
                                },
                            ],
                        }
                    ],
                }
            ],
        },
        {
            "skill": "reading",
            "duration_minutes": 60,
            "parts": [
                {
                    "order": 1,
                    "passage_title": "The Urban Heat Island Effect",
                    "passage_text": READING_PASSAGE,
                    "question_groups": [
                        {
                            "question_type": "true_false_notgiven",
                            "instructions": (
                                "Do the following statements agree with the "
                                "information in the passage? Write TRUE, FALSE or "
                                "NOT GIVEN."
                            ),
                            "questions": [
                                {
                                    "key": "R1",
                                    "number": 1,
                                    "prompt": (
                                        "The temperature gap between a city and nearby "
                                        "farmland can be more than eight degrees Celsius."
                                    ),
                                    "accepted_answers": ["TRUE"],
                                },
                                {
                                    "key": "R2",
                                    "number": 2,
                                    "prompt": (
                                        "Vegetation cools the air primarily by providing shade."
                                    ),
                                    "accepted_answers": ["FALSE"],
                                },
                                {
                                    "key": "R3",
                                    "number": 3,
                                    "prompt": (
                                        "Reflective roofing is now required by law in most "
                                        "large cities."
                                    ),
                                    "accepted_answers": ["NOT GIVEN"],
                                },
                                {
                                    "key": "R4",
                                    "number": 4,
                                    "prompt": (
                                        "Greener districts within a city tend to be the "
                                        "wealthier ones."
                                    ),
                                    "accepted_answers": ["TRUE"],
                                },
                            ],
                        },
                        {
                            "question_type": "short_answer",
                            "instructions": "Answer with NO MORE THAN TWO WORDS from the passage.",
                            "questions": [
                                {
                                    "key": "R5",
                                    "number": 5,
                                    "prompt": (
                                        "What term do climatologists use for radiation "
                                        "trapped between tall buildings?"
                                    ),
                                    "accepted_answers": ["urban canyon"],
                                },
                                {
                                    "key": "R6",
                                    "number": 6,
                                    "prompt": (
                                        "By what process do plants release water vapour?"
                                    ),
                                    "accepted_answers": ["evapotranspiration"],
                                },
                            ],
                        },
                    ],
                }
            ],
        },
        {
            "skill": "writing",
            "duration_minutes": 60,
            "parts": [
                {
                    "order": 1,
                    "part_key": "writing_task_1",
                    "prompt": (
                        "The chart below shows the average summer night-time "
                        "temperature recorded in a city centre and in surrounding "
                        "farmland between 1990 and 2020. Summarise the information "
                        "by selecting and reporting the main features, and make "
                        "comparisons where relevant. Write at least 150 words."
                    ),
                    "image_url": "",
                    "min_words": 150,
                    "suggested_minutes": 20,
                },
                {
                    "order": 2,
                    "part_key": "writing_task_2",
                    "prompt": (
                        "Some people believe that cities should limit private car "
                        "use in order to reduce pollution and make urban areas more "
                        "liveable. Others argue that such restrictions unfairly "
                        "penalise people who depend on their cars. Discuss both "
                        "views and give your own opinion. Write at least 250 words."
                    ),
                    "min_words": 250,
                    "suggested_minutes": 40,
                },
            ],
        },
        {
            "skill": "speaking",
            "duration_minutes": 14,
            "parts": [
                {
                    "order": 1,
                    "part_key": "speaking_part_1",
                    "prompt": (
                        "Let's talk about where you live. Do you live in a city or "
                        "a smaller town? What do you like most about it? Is it a "
                        "good place for young people?"
                    ),
                },
                {
                    "order": 2,
                    "part_key": "speaking_part_2",
                    "cue_card": (
                        "Describe a place in your city that you think should be "
                        "improved. You should say: where it is, what it is like "
                        "now, how it could be improved, and explain why you think "
                        "the improvement matters."
                    ),
                    "prep_seconds": 60,
                    "speak_seconds": 120,
                },
                {
                    "order": 3,
                    "part_key": "speaking_part_3",
                    "prompt": (
                        "Who should pay for improvements to public spaces — local "
                        "government, residents, or private business? Do you think "
                        "cities will become more or less pleasant to live in over "
                        "the next fifty years?"
                    ),
                },
            ],
        },
    ]
}


async def main() -> None:
    async with AsyncSessionLocal() as db:
        existing = await db.execute(select(IeltsTest).where(IeltsTest.title == TITLE))
        test = existing.scalar_one_or_none()
        if test:
            test.content = CONTENT
            action = "updated"
        else:
            test = IeltsTest(
                title=TITLE,
                description=(
                    "A full Academic paper covering all four skills. Listening and "
                    "Reading are scored from the answer key; Writing and Speaking "
                    "are graded against the band descriptors."
                ),
                test_type="academic",
                skill_scope="full",
                target_band="6.0-7.0",
                slug="ielts-academic-practice-1",
                content=CONTENT,
                is_published=True,
            )
            db.add(test)
            action = "created"
        await db.commit()
        await db.refresh(test)

    listening = sum(
        len(g["questions"])
        for s in CONTENT["sections"]
        if s["skill"] == "listening"
        for p in s["parts"]
        for g in p["question_groups"]
    )
    reading = sum(
        len(g["questions"])
        for s in CONTENT["sections"]
        if s["skill"] == "reading"
        for p in s["parts"]
        for g in p["question_groups"]
    )
    print(f"{action}: {TITLE} ({test.id})")
    print(f"  listening {listening} questions, reading {reading} questions")
    print("  writing 2 tasks, speaking 3 parts")
    print("  NOTE: the listening audio_url is a placeholder — upload a recording")
    print("        in the admin IELTS page and paste the returned URL.")


if __name__ == "__main__":
    asyncio.run(main())
