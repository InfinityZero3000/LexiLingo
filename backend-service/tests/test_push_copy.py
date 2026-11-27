from app.services.push_copy import push_language, review_reminder_copy, word_of_day_copy


def test_review_reminder_names_the_due_words_in_the_learners_language():
    title, body = review_reminder_copy("vi", 5, ["resilient", "approve", "thrive"])

    assert title == "📚 5 từ đang chờ bạn ôn"
    assert body == "resilient, approve, thrive +2 — Ôn 2 phút để nhớ lâu hơn."


def test_review_reminder_singular_and_without_words():
    title, body = review_reminder_copy("en", 1, [])

    assert title == "📚 1 word is waiting for you"
    assert body == "A 2-minute review keeps them fresh."


def test_unshipped_language_falls_back_to_english():
    assert push_language("de") == "en"
    assert push_language("vi-VN") == "vi"
    assert push_language(None) == "en"


def test_word_of_day_uses_the_translation_for_the_learners_language():
    title, body = word_of_day_copy(
        "vi",
        word="book",
        pronunciation="/bʊk/",
        translation={"vi": "quyển sách"},
        definition="a written work",
    )

    assert title == "✨ Từ của ngày: book"
    assert body == "/bʊk/ · quyển sách"


def test_word_of_day_without_a_translation_uses_the_definition_and_stays_short():
    _, body = word_of_day_copy(
        "ko",
        word="book",
        pronunciation=None,
        translation={"vi": "quyển sách"},
        definition="x" * 300,
    )

    assert len(body) <= 120
    assert body.endswith("…")


def test_starter_reward_follows_the_language_and_falls_back_to_english():
    from app.services.push_copy import starter_reward_copy

    assert starter_reward_copy("vi", 100) == (
        "🎁 Quà chào mừng!",
        "100 Gem đã được thêm vào ví của bạn.",
    )
    assert starter_reward_copy("ko-KR", 100)[1] == "젬 100개가 지갑에 추가됐어요."
    assert starter_reward_copy(None, 100)[0] == "🎁 Welcome gift!"


def test_streak_and_nurture_nudges_are_written_in_the_learners_language():
    from app.services.push_copy import nudge_copy

    assert nudge_copy("streak_at_risk", "vi", days=12) == (
        "🔥 Đừng để mất chuỗi 12 ngày!",
        "Chỉ một bài học ngắn là giữ được chuỗi của bạn hôm nay.",
    )
    assert nudge_copy("nurture_d1", "ja")[0] == "🚀 最初のレッスンの準備ができました"
    assert nudge_copy("weekly_summary", "en", days=4, xp=1250)[1] == (
        "1,250 XP and a 4-day streak in the last 7 days."
    )
    assert nudge_copy("streak_risk_email", "de", days=3)[0] == "🔥 Keep your streak alive"
