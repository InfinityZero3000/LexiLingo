import React, { useState } from "react";
import { Award, Brain, RotateCcw, Trophy, X, Zap } from "lucide-react";

import {
  createRankingAgentJob,
  type RankingAgentJob,
  type RankingAgentJobType,
} from "../../lib/rankingAgentApi";
import { useI18n } from "../../lib/i18n";

const LEAGUES = [
  "bronze", "silver", "gold", "platinum", "sapphire", "ruby", "amethyst", "master",
] as const;
const CEFR_LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"] as const;

type Props = {
  onClose: () => void;
  onJobCreated: (job: RankingAgentJob) => void;
};

type Tab = RankingAgentJobType;

const TAB_INFO: Record<Tab, { label: string; icon: React.ReactNode; description: string }> = {
  league_reset: {
    label: "League Reset",
    icon: <RotateCcw className="w-4 h-4" />,
    description: "Calculate weekly promotions and demotions across all leagues.",
  },
  xp_event: {
    label: "XP Event",
    icon: <Zap className="w-4 h-4" />,
    description: "Grant a time-limited XP boost to a group of users.",
  },
  achievement_batch: {
    label: "Achievement Batch",
    icon: <Award className="w-4 h-4" />,
    description: "Grant achievements in bulk to users matching custom criteria.",
  },
};

export function RankingAgentModal({ onClose, onJobCreated }: Props) {
  const { t } = useI18n();
  const [activeTab, setActiveTab] = useState<Tab>("league_reset");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // League Reset config
  const [weekStart, setWeekStart] = useState("");

  // XP Event config
  const [eventName, setEventName] = useState("Weekend Boost");
  const [multiplier, setMultiplier] = useState(2.0);
  const [durationHours, setDurationHours] = useState(48);
  const [target, setTarget] = useState("all");
  const [targetLeague, setTargetLeague] = useState("gold");
  const [targetCefr, setTargetCefr] = useState("B1");

  // AI insights
  const [useAiInsights, setUseAiInsights] = useState(false);

  // Achievement Batch config
  const [slugInput, setSlugInput] = useState("");
  const [minStreak, setMinStreak] = useState("");
  const [minVocab, setMinVocab] = useState("");
  const [selectedLeagues, setSelectedLeagues] = useState<string[]>([]);
  const [selectedCefr, setSelectedCefr] = useState<string[]>([]);

  function buildTarget(): string {
    if (target === "all") return "all";
    if (target === "league") return `league:${targetLeague}`;
    return `cefr:${targetCefr}`;
  }

  async function handleSubmit() {
    setError(null);
    setSubmitting(true);
    try {
      let payload: Parameters<typeof createRankingAgentJob>[0];

      if (activeTab === "league_reset") {
        payload = {
          job_type: "league_reset",
          config: weekStart ? { week_start: weekStart } : {},
          use_ai_insights: useAiInsights,
        };
      } else if (activeTab === "xp_event") {
        payload = {
          job_type: "xp_event",
          config: {
            name: eventName,
            multiplier,
            duration_hours: durationHours,
            target: buildTarget(),
          },
          use_ai_insights: useAiInsights,
        };
      } else {
        const slugs = slugInput
          .split(/[\s,]+/)
          .map((s) => s.trim())
          .filter(Boolean);
        if (slugs.length === 0) {
          setError("Enter at least one achievement slug.");
          setSubmitting(false);
          return;
        }
        const criteria: Record<string, unknown> = {};
        if (minStreak) criteria.min_streak = parseInt(minStreak, 10);
        if (minVocab) criteria.min_vocabulary_mastered = parseInt(minVocab, 10);
        if (selectedLeagues.length) criteria.leagues = selectedLeagues;
        if (selectedCefr.length) criteria.cefr_levels = selectedCefr;

        payload = {
          job_type: "achievement_batch",
          config: { achievement_slugs: slugs, criteria },
          use_ai_insights: useAiInsights,
        };
      }

      const job = await createRankingAgentJob(payload);
      onJobCreated(job);
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to create job.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-xl shadow-2xl w-full max-w-xl flex flex-col max-h-[90vh]">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b">
          <div className="flex items-center gap-2">
            <Trophy className="w-5 h-5 text-amber-500" />
            <h2 className="text-lg font-semibold text-gray-900">
              New Ranking Agent Job
            </h2>
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Tabs */}
        <div className="flex border-b px-6">
          {(Object.keys(TAB_INFO) as Tab[]).map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`flex items-center gap-1.5 px-4 py-3 text-sm font-medium border-b-2 transition-colors ${
                activeTab === tab
                  ? "border-blue-600 text-blue-600"
                  : "border-transparent text-gray-500 hover:text-gray-700"
              }`}
            >
              {TAB_INFO[tab].icon}
              {TAB_INFO[tab].label}
            </button>
          ))}
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto px-6 py-5 space-y-4">
          <p className="text-sm text-gray-500">{TAB_INFO[activeTab].description}</p>

          {activeTab === "league_reset" && (
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Target week (optional)
              </label>
              <input
                type="date"
                value={weekStart}
                onChange={(e) => setWeekStart(e.target.value)}
                className="w-full border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                placeholder="Leave blank for last completed week"
              />
              <p className="text-xs text-gray-400 mt-1">
                Leave blank to use the most recently completed week (last Monday).
              </p>
            </div>
          )}

          {activeTab === "xp_event" && (
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Event name
                </label>
                <input
                  type="text"
                  value={eventName}
                  onChange={(e) => setEventName(e.target.value)}
                  className="w-full border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Multiplier (×)
                  </label>
                  <input
                    type="number"
                    min={1.1}
                    max={5}
                    step={0.1}
                    value={multiplier}
                    onChange={(e) => setMultiplier(parseFloat(e.target.value))}
                    className="w-full border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Duration (hours)
                  </label>
                  <input
                    type="number"
                    min={1}
                    max={168}
                    value={durationHours}
                    onChange={(e) => setDurationHours(parseInt(e.target.value, 10))}
                    className="w-full border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                </div>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Target
                </label>
                <div className="flex gap-2 flex-wrap">
                  {["all", "league", "cefr"].map((t) => (
                    <button
                      key={t}
                      onClick={() => setTarget(t)}
                      className={`px-3 py-1.5 rounded-full text-sm border transition-colors ${
                        target === t
                          ? "bg-blue-600 text-white border-blue-600"
                          : "bg-white text-gray-600 border-gray-300 hover:border-blue-400"
                      }`}
                    >
                      {t === "all" ? "All users" : t === "league" ? "By league" : "By CEFR"}
                    </button>
                  ))}
                </div>
                {target === "league" && (
                  <select
                    value={targetLeague}
                    onChange={(e) => setTargetLeague(e.target.value)}
                    className="mt-2 w-full border rounded-lg px-3 py-2 text-sm capitalize"
                  >
                    {LEAGUES.map((l) => (
                      <option key={l} value={l} className="capitalize">
                        {l.charAt(0).toUpperCase() + l.slice(1)}
                      </option>
                    ))}
                  </select>
                )}
                {target === "cefr" && (
                  <select
                    value={targetCefr}
                    onChange={(e) => setTargetCefr(e.target.value)}
                    className="mt-2 w-full border rounded-lg px-3 py-2 text-sm"
                  >
                    {CEFR_LEVELS.map((l) => (
                      <option key={l} value={l}>
                        {l}
                      </option>
                    ))}
                  </select>
                )}
              </div>
            </div>
          )}

          {activeTab === "achievement_batch" && (
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Achievement slugs
                </label>
                <textarea
                  rows={2}
                  value={slugInput}
                  onChange={(e) => setSlugInput(e.target.value)}
                  placeholder="streak_30, vocab_master_100"
                  className="w-full border rounded-lg px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
                <p className="text-xs text-gray-400 mt-1">
                  Comma or space separated slug names.
                </p>
              </div>
              <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                Eligibility criteria (optional — leave blank for all users)
              </p>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Min streak (days)
                  </label>
                  <input
                    type="number"
                    min={0}
                    value={minStreak}
                    onChange={(e) => setMinStreak(e.target.value)}
                    placeholder="e.g. 30"
                    className="w-full border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Min vocab mastered
                  </label>
                  <input
                    type="number"
                    min={0}
                    value={minVocab}
                    onChange={(e) => setMinVocab(e.target.value)}
                    placeholder="e.g. 100"
                    className="w-full border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                </div>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Leagues (optional)
                </label>
                <div className="flex flex-wrap gap-1.5">
                  {LEAGUES.map((l) => (
                    <button
                      key={l}
                      onClick={() =>
                        setSelectedLeagues((prev) =>
                          prev.includes(l) ? prev.filter((x) => x !== l) : [...prev, l]
                        )
                      }
                      className={`px-2.5 py-1 rounded-full text-xs border capitalize transition-colors ${
                        selectedLeagues.includes(l)
                          ? "bg-blue-600 text-white border-blue-600"
                          : "bg-white text-gray-600 border-gray-300 hover:border-blue-400"
                      }`}
                    >
                      {l}
                    </button>
                  ))}
                </div>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  CEFR levels (optional)
                </label>
                <div className="flex flex-wrap gap-1.5">
                  {CEFR_LEVELS.map((l) => (
                    <button
                      key={l}
                      onClick={() =>
                        setSelectedCefr((prev) =>
                          prev.includes(l) ? prev.filter((x) => x !== l) : [...prev, l]
                        )
                      }
                      className={`px-2.5 py-1 rounded-full text-xs border transition-colors ${
                        selectedCefr.includes(l)
                          ? "bg-blue-600 text-white border-blue-600"
                          : "bg-white text-gray-600 border-gray-300 hover:border-blue-400"
                      }`}
                    >
                      {l}
                    </button>
                  ))}
                </div>
              </div>
            </div>
          )}

          {/* AI Insights toggle */}
          <div className="flex items-center justify-between rounded-lg border border-purple-100 bg-purple-50 px-4 py-3">
            <div className="flex items-center gap-2">
              <Brain className="w-4 h-4 text-purple-500" />
              <div>
                <p className="text-sm font-medium text-purple-900">AI Insights (Groq)</p>
                <p className="text-xs text-purple-600">
                  Generate a short Groq-powered commentary during the validating phase.
                  Skipped gracefully if keys are rate-limited.
                </p>
              </div>
            </div>
            <button
              type="button"
              role="switch"
              aria-checked={useAiInsights}
              onClick={() => setUseAiInsights((v) => !v)}
              className={`relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors focus:outline-none focus:ring-2 focus:ring-purple-500 focus:ring-offset-2 ${
                useAiInsights ? "bg-purple-600" : "bg-gray-200"
              }`}
            >
              <span
                className={`pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow ring-0 transition-transform ${
                  useAiInsights ? "translate-x-4" : "translate-x-0"
                }`}
              />
            </button>
          </div>

          {error && (
            <div className="text-sm text-red-600 bg-red-50 rounded-lg px-3 py-2">
              {error}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex justify-end gap-3 px-6 py-4 border-t">
          <button
            onClick={onClose}
            className="px-4 py-2 text-sm text-gray-600 hover:text-gray-800 rounded-lg border border-gray-300 hover:border-gray-400 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleSubmit}
            disabled={submitting}
            className="px-5 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 transition-colors font-medium"
          >
            {submitting ? "Creating…" : "Create & Preview"}
          </button>
        </div>
      </div>
    </div>
  );
}
