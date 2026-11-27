"""Learner-facing push copy for the vocabulary notifications, in the app's 7 locales.

The server does not know the UI language, so a push follows `native_language`
and falls back to English for a language the app does not ship.
"""

from __future__ import annotations

SUPPORTED = ("vi", "en", "es", "fr", "ja", "ko", "zh")

_REVIEW_TITLE = {
    "vi": ("📚 1 từ đang chờ bạn ôn", "📚 {count} từ đang chờ bạn ôn"),
    "en": ("📚 1 word is waiting for you", "📚 {count} words are waiting for you"),
    "es": ("📚 1 palabra te espera", "📚 {count} palabras te esperan"),
    "fr": ("📚 1 mot vous attend", "📚 {count} mots vous attendent"),
    "ja": ("📚 復習を待つ単語が1語あります", "📚 復習を待つ単語が{count}語あります"),
    "ko": ("📚 복습할 단어 1개가 기다리고 있어요", "📚 복습할 단어 {count}개가 기다리고 있어요"),
    "zh": ("📚 有 1 个单词等你复习", "📚 有 {count} 个单词等你复习"),
}

_REVIEW_NUDGE = {
    "vi": "Ôn 2 phút để nhớ lâu hơn.",
    "en": "A 2-minute review keeps them fresh.",
    "es": "Un repaso de 2 minutos las mantiene frescas.",
    "fr": "2 minutes de révision pour bien les retenir.",
    "ja": "2分の復習で記憶に定着させましょう。",
    "ko": "2분만 복습하면 오래 기억할 수 있어요.",
    "zh": "花 2 分钟复习，记得更牢。",
}

_WORD_OF_DAY_TITLE = {
    "vi": "✨ Từ của ngày: {word}",
    "en": "✨ Word of the day: {word}",
    "es": "✨ Palabra del día: {word}",
    "fr": "✨ Mot du jour : {word}",
    "ja": "✨ 今日の単語：{word}",
    "ko": "✨ 오늘의 단어: {word}",
    "zh": "✨ 今日单词：{word}",
}

# Same wording as the app's welcome dialog (gamification.starterReward), so
# the push, the inbox row and the dialog say one thing.
_STARTER_REWARD = {
    "vi": ("🎁 Quà chào mừng!", "{gems} Gem đã được thêm vào ví của bạn."),
    "en": ("🎁 Welcome gift!", "{gems} Gems were added to your wallet."),
    "es": ("🎁 ¡Regalo de bienvenida!", "Se añadieron {gems} gemas a tu cartera."),
    "fr": ("🎁 Cadeau de bienvenue !", "{gems} gemmes ont été ajoutées à votre portefeuille."),
    "ja": ("🎁 ウェルカムギフト！", "{gems} ジェムがウォレットに追加されました。"),
    "ko": ("🎁 환영 선물!", "젬 {gems}개가 지갑에 추가됐어요."),
    "zh": ("🎁 欢迎礼物！", "{gems} 颗宝石已存入你的钱包。"),
}

_BODY_LIMIT = 120


def push_language(native_language: str | None) -> str:
    if not isinstance(native_language, str):
        return "en"
    lang = native_language.strip().lower().split("-")[0].split("_")[0]
    return lang if lang in SUPPORTED else "en"


def review_reminder_copy(lang: str, due_count: int, words: list[str]) -> tuple[str, str]:
    lang = push_language(lang)
    one, many = _REVIEW_TITLE[lang]
    title = one if due_count == 1 else many.format(count=due_count)
    nudge = _REVIEW_NUDGE[lang]
    if not words:
        return title, nudge
    named = ", ".join(words)
    if due_count > len(words):
        named += f" +{due_count - len(words)}"
    return title, f"{named} — {nudge}"


def word_of_day_copy(
    lang: str,
    *,
    word: str,
    pronunciation: str | None,
    translation: dict | None,
    definition: str | None,
) -> tuple[str, str]:
    lang = push_language(lang)
    title = _WORD_OF_DAY_TITLE[lang].format(word=word)
    meaning = (translation or {}).get(lang) if lang != "en" else None
    if not isinstance(meaning, str) or not meaning.strip():
        meaning = definition or ""
    parts = [p.strip() for p in (pronunciation, meaning) if p and p.strip()]
    body = " · ".join(parts)
    if len(body) > _BODY_LIMIT:
        body = body[: _BODY_LIMIT - 1].rstrip() + "…"
    return title, body


def starter_reward_copy(lang: str | None, gems: int) -> tuple[str, str]:
    title, body = _STARTER_REWARD[push_language(lang)]
    return title, body.format(gems=gems)


# Streak and activation nudges: {days}, {xp} are filled in by the caller.
_NUDGES: dict[str, dict[str, tuple[str, str]]] = {
    # Push from the 20:00 UTC streak task.
    "streak_at_risk": {
        "vi": ("🔥 Đừng để mất chuỗi {days} ngày!", "Chỉ một bài học ngắn là giữ được chuỗi của bạn hôm nay."),
        "en": ("🔥 Don't lose your {days}-day streak!", "One quick lesson keeps it alive today."),
        "es": ("🔥 ¡No pierdas tu racha de {days} días!", "Una lección rápida basta para mantenerla hoy."),
        "fr": ("🔥 Ne perdez pas votre série de {days} jours !", "Une petite leçon suffit pour la garder aujourd'hui."),
        "ja": ("🔥 {days}日連続記録を途切れさせないで！", "短いレッスン1つで今日の記録を守れます。"),
        "ko": ("🔥 {days}일 연속 기록을 지켜요!", "짧은 레슨 하나면 오늘도 이어갈 수 있어요."),
        "zh": ("🔥 别让 {days} 天连续记录中断！", "完成一节小课，今天的记录就能保住。"),
    },
    "nurture_d1": {
        "vi": ("🚀 Bài học đầu tiên đã sẵn sàng", "Một bài ngắn là đủ để bắt đầu. Chạm để học ngay."),
        "en": ("🚀 Your first lesson is ready", "One short lesson is enough to begin. Tap to start."),
        "es": ("🚀 Tu primera lección está lista", "Una lección corta basta para empezar. Toca para comenzar."),
        "fr": ("🚀 Votre première leçon est prête", "Une courte leçon suffit pour commencer. Touchez pour démarrer."),
        "ja": ("🚀 最初のレッスンの準備ができました", "短いレッスン1つで始められます。タップしてスタート。"),
        "ko": ("🚀 첫 레슨이 준비됐어요", "짧은 레슨 하나면 시작할 수 있어요. 눌러서 시작하세요."),
        "zh": ("🚀 你的第一节课已准备好", "一节短课就能开始。点击立即学习。"),
    },
    "nurture_d3": {
        "vi": ("👋 Vẫn muốn bắt đầu chứ?", "Bài học đầu tiên vẫn đang chờ bạn. Năm phút là đủ."),
        "en": ("👋 Still want to start?", "Your first lesson is waiting. Five minutes is enough."),
        "es": ("👋 ¿Aún quieres empezar?", "Tu primera lección te espera. Cinco minutos bastan."),
        "fr": ("👋 Toujours partant ?", "Votre première leçon vous attend. Cinq minutes suffisent."),
        "ja": ("👋 まだ始めてみませんか？", "最初のレッスンが待っています。5分で十分です。"),
        "ko": ("👋 아직 시작할 생각 있으세요?", "첫 레슨이 기다리고 있어요. 5분이면 충분해요."),
        "zh": ("👋 还想开始吗？", "你的第一节课还在等你，五分钟就够。"),
    },
    "streak_risk_email": {
        "vi": ("🔥 Giữ chuỗi ngày học của bạn", "Chuỗi {days} ngày sẽ kết thúc tối nay. Chỉ cần vài phút thôi."),
        "en": ("🔥 Keep your streak alive", "Your {days}-day streak ends tonight. A few minutes is enough."),
        "es": ("🔥 Mantén viva tu racha", "Tu racha de {days} días termina esta noche. Bastan unos minutos."),
        "fr": ("🔥 Gardez votre série", "Votre série de {days} jours se termine ce soir. Quelques minutes suffisent."),
        "ja": ("🔥 連続記録を守ろう", "{days}日連続の記録は今夜で途切れます。数分で大丈夫です。"),
        "ko": ("🔥 연속 기록을 이어가요", "{days}일 연속 기록이 오늘 밤 끊겨요. 몇 분이면 충분해요."),
        "zh": ("🔥 保住你的连续记录", "你的 {days} 天连续记录今晚就要中断了，几分钟就够。"),
    },
    "weekly_summary": {
        "vi": ("📊 Tuần học của bạn trên LexiLingo", "{xp} XP và chuỗi {days} ngày trong 7 ngày qua."),
        "en": ("📊 Your week in LexiLingo", "{xp} XP and a {days}-day streak in the last 7 days."),
        "es": ("📊 Tu semana en LexiLingo", "{xp} XP y una racha de {days} días en los últimos 7 días."),
        "fr": ("📊 Votre semaine sur LexiLingo", "{xp} XP et une série de {days} jours ces 7 derniers jours."),
        "ja": ("📊 LexiLingoでの1週間", "この7日間で {xp} XP、{days}日連続を達成しました。"),
        "ko": ("📊 LexiLingo에서 보낸 한 주", "지난 7일 동안 {xp} XP, {days}일 연속 기록을 달성했어요."),
        "zh": ("📊 你在 LexiLingo 的一周", "过去 7 天获得 {xp} XP，连续学习 {days} 天。"),
    },
}


def nudge_copy(kind: str, lang: str | None, *, days: int = 0, xp: int = 0) -> tuple[str, str]:
    title, body = _NUDGES[kind][push_language(lang)]
    values = {"days": days, "xp": f"{xp:,}"}
    return title.format(**values), body.format(**values)
