import React, { useState } from "react";
import { Bell, Calendar, MessageSquare, Radio, Sparkles, X } from "lucide-react";

import {
  createNotificationCampaignJob,
  type NotificationCampaignJob,
  type NotificationCampaignJobType,
} from "../../lib/notificationCampaignApi";

const LEAGUES = [
  "bronze", "silver", "gold", "platinum", "sapphire", "ruby", "amethyst", "master",
] as const;
const CEFR_LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"] as const;

type Props = {
  onClose: () => void;
  onJobCreated: (job: NotificationCampaignJob) => void;
};

type Tab = NotificationCampaignJobType;

const TAB_INFO: Record<Tab, { label: string; icon: React.ReactNode; description: string }> = {
  targeted_push: {
    label: "Targeted Push",
    icon: <Bell className="w-4 h-4" />,
    description: "Send an FCM push notification to a filtered user segment.",
  },
  in_app_broadcast: {
    label: "In-App Broadcast",
    icon: <MessageSquare className="w-4 h-4" />,
    description: "Create persisted in-app notifications visible in the notification feed.",
  },
  scheduled_push: {
    label: "Scheduled Push",
    icon: <Calendar className="w-4 h-4" />,
    description: "Schedule a push notification to be sent at a specific date and time.",
  },
};

export function NotificationCampaignModal({ onClose, onJobCreated }: Props) {
  const [activeTab, setActiveTab] = useState<Tab>("targeted_push");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Content
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [notifType, setNotifType] = useState("campaign");
  const [deepLink, setDeepLink] = useState("");
  const [useAiCopy, setUseAiCopy] = useState(false);

  // Audience
  const [audienceType, setAudienceType] = useState<"all" | "segment">("all");
  const [selectedLeagues, setSelectedLeagues] = useState<string[]>([]);
  const [selectedCefr, setSelectedCefr] = useState<string[]>([]);
  const [minStreak, setMinStreak] = useState("");
  const [inactiveDays, setInactiveDays] = useState("");

  // Scheduled push
  const [sendAt, setSendAt] = useState("");

  function toggleLeague(l: string) {
    setSelectedLeagues((prev) =>
      prev.includes(l) ? prev.filter((x) => x !== l) : [...prev, l]
    );
  }

  function toggleCefr(l: string) {
    setSelectedCefr((prev) =>
      prev.includes(l) ? prev.filter((x) => x !== l) : [...prev, l]
    );
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!title.trim() || !body.trim()) {
      setError("Title and body are required.");
      return;
    }

    const audienceFilters: Record<string, unknown> = { has_fcm_token: true };
    if (audienceType === "segment") {
      if (selectedLeagues.length) audienceFilters.leagues = selectedLeagues;
      if (selectedCefr.length) audienceFilters.cefr_levels = selectedCefr;
      if (minStreak) audienceFilters.min_streak = parseInt(minStreak, 10);
      if (inactiveDays) audienceFilters.inactive_days = parseInt(inactiveDays, 10);
    }

    const config: Record<string, unknown> = {
      audience: { type: audienceType, filters: audienceFilters },
      content: {
        title: title.trim(),
        body: body.trim(),
        notification_type: notifType,
        deep_link: deepLink.trim() || null,
        use_ai_copy: useAiCopy,
      },
    };

    if (activeTab === "scheduled_push" && sendAt) {
      config.send_at = new Date(sendAt).toISOString();
    }

    setSubmitting(true);
    setError(null);
    try {
      const job = await createNotificationCampaignJob({
        job_type: activeTab,
        config,
      });
      onJobCreated(job);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Failed to create job");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-xl shadow-2xl w-full max-w-2xl max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between px-6 py-4 border-b">
          <div className="flex items-center gap-2">
            <Radio className="w-5 h-5 text-blue-500" />
            <h2 className="font-semibold text-gray-900">Tạo Notification Campaign</h2>
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="flex border-b px-6 gap-1 pt-2">
          {(Object.keys(TAB_INFO) as Tab[]).map((tab) => (
            <button
              key={tab}
              type="button"
              onClick={() => setActiveTab(tab)}
              className={`flex items-center gap-1.5 px-3 py-2 text-sm font-medium rounded-t-lg border-b-2 transition-colors ${
                activeTab === tab
                  ? "border-blue-500 text-blue-600"
                  : "border-transparent text-gray-500 hover:text-gray-700"
              }`}
            >
              {TAB_INFO[tab].icon}
              {TAB_INFO[tab].label}
            </button>
          ))}
        </div>

        <form onSubmit={handleSubmit} className="px-6 py-5 space-y-5">
          <p className="text-sm text-gray-500">{TAB_INFO[activeTab].description}</p>

          <div className="space-y-4 border rounded-lg p-4">
            <h3 className="text-sm font-semibold text-gray-700">Nội dung thông báo</h3>

            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">
                Tiêu đề <span className="text-red-500">*</span>
              </label>
              <input
                className="input-field"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                maxLength={100}
                placeholder="Ví dụ: Weekend Boost đã bắt đầu!"
              />
              <p className="text-xs text-gray-400 mt-0.5">{title.length}/100</p>
            </div>

            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">
                Nội dung <span className="text-red-500">*</span>
              </label>
              <textarea
                className="input-field min-h-[80px] resize-none"
                value={body}
                onChange={(e) => setBody(e.target.value)}
                maxLength={300}
                placeholder="Ví dụ: Học ngay hôm nay để nhận 2× XP trong 48 giờ!"
              />
              <p className="text-xs text-gray-400 mt-0.5">{body.length}/300</p>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Loại thông báo</label>
                <input
                  className="input-field"
                  value={notifType}
                  onChange={(e) => setNotifType(e.target.value)}
                  placeholder="campaign"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Deep link (tùy chọn)</label>
                <input
                  className="input-field"
                  value={deepLink}
                  onChange={(e) => setDeepLink(e.target.value)}
                  placeholder="/vocabulary"
                />
              </div>
            </div>

            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={useAiCopy}
                onChange={(e) => setUseAiCopy(e.target.checked)}
                className="w-4 h-4 rounded text-blue-500"
              />
              <span className="text-sm text-gray-700 flex items-center gap-1">
                <Sparkles className="w-3.5 h-3.5 text-purple-500" />
                Dùng AI (Groq) để cải thiện nội dung
              </span>
            </label>
          </div>

          <div className="space-y-3 border rounded-lg p-4">
            <h3 className="text-sm font-semibold text-gray-700">Đối tượng</h3>

            <div className="flex gap-3">
              {(["all", "segment"] as const).map((t) => (
                <label key={t} className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="radio"
                    checked={audienceType === t}
                    onChange={() => setAudienceType(t)}
                    className="w-4 h-4 text-blue-500"
                  />
                  <span className="text-sm text-gray-700">
                    {t === "all" ? "Tất cả users" : "Lọc theo tiêu chí"}
                  </span>
                </label>
              ))}
            </div>

            {audienceType === "segment" && (
              <div className="space-y-3 pt-2">
                <div>
                  <label className="block text-xs font-medium text-gray-600 mb-1.5">League</label>
                  <div className="flex flex-wrap gap-1.5">
                    {LEAGUES.map((l) => (
                      <button
                        key={l}
                        type="button"
                        onClick={() => toggleLeague(l)}
                        className={`px-2.5 py-1 text-xs rounded-full border font-medium transition-colors ${
                          selectedLeagues.includes(l)
                            ? "bg-blue-500 text-white border-blue-500"
                            : "border-gray-300 text-gray-600 hover:border-blue-400"
                        }`}
                      >
                        {l}
                      </button>
                    ))}
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-medium text-gray-600 mb-1.5">CEFR Level</label>
                  <div className="flex gap-1.5">
                    {CEFR_LEVELS.map((l) => (
                      <button
                        key={l}
                        type="button"
                        onClick={() => toggleCefr(l)}
                        className={`px-2.5 py-1 text-xs rounded-full border font-medium transition-colors ${
                          selectedCefr.includes(l)
                            ? "bg-indigo-500 text-white border-indigo-500"
                            : "border-gray-300 text-gray-600 hover:border-indigo-400"
                        }`}
                      >
                        {l}
                      </button>
                    ))}
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">Min streak (ngày)</label>
                    <input
                      type="number"
                      className="input-field"
                      value={minStreak}
                      onChange={(e) => setMinStreak(e.target.value)}
                      min={0}
                      placeholder="Tùy chọn"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">Không hoạt động (ngày)</label>
                    <input
                      type="number"
                      className="input-field"
                      value={inactiveDays}
                      onChange={(e) => setInactiveDays(e.target.value)}
                      min={1}
                      placeholder="Tùy chọn"
                    />
                  </div>
                </div>
              </div>
            )}
          </div>

          {activeTab === "scheduled_push" && (
            <div className="space-y-1 border rounded-lg p-4">
              <h3 className="text-sm font-semibold text-gray-700">Lên lịch gửi</h3>
              <label className="block text-xs font-medium text-gray-600 mb-1">Thời gian gửi (UTC)</label>
              <input
                type="datetime-local"
                className="input-field"
                value={sendAt}
                onChange={(e) => setSendAt(e.target.value)}
              />
            </div>
          )}

          {error && (
            <p className="text-sm text-red-600 bg-red-50 rounded-lg px-3 py-2">{error}</p>
          )}

          <div className="flex justify-end gap-3 pt-2">
            <button type="button" onClick={onClose} className="ghost-button">
              Hủy
            </button>
            <button type="submit" disabled={submitting} className="primary-button">
              {submitting ? "Đang tạo..." : "Tạo Job"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
