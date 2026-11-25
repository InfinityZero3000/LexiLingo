import React, { useCallback, useEffect, useRef, useState } from "react";
import {
  AlertTriangle,
  Award,
  Brain,
  CheckCircle,
  ChevronDown,
  ChevronUp,
  Clock,
  RotateCcw,
  Trophy,
  X,
  XCircle,
  Zap,
} from "lucide-react";

import {
  applyRankingAgentJob,
  cancelRankingAgentJob,
  canApplyRankingAgentJob,
  getRankingAgentJob,
  isRankingAgentJobActive,
  JOB_TYPE_LABELS,
  retryRankingAgentJob,
  STATUS_LABELS,
  type RankingAgentJob,
} from "../../lib/rankingAgentApi";

const POLL_MS = 2500;

type Props = {
  job: RankingAgentJob;
  onClose: () => void;
  onJobUpdated: (job: RankingAgentJob) => void;
};

export function RankingAgentDrawer({ job: initialJob, onClose, onJobUpdated }: Props) {
  const [job, setJob] = useState<RankingAgentJob>(initialJob);
  const [applying, setApplying] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [previewExpanded, setPreviewExpanded] = useState(true);
  const pollRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const updateJob = useCallback(
    (updated: RankingAgentJob) => {
      setJob(updated);
      onJobUpdated(updated);
    },
    [onJobUpdated]
  );

  useEffect(() => {
    if (!isRankingAgentJobActive(job.status)) return;
    pollRef.current = setInterval(async () => {
      try {
        const updated = await getRankingAgentJob(job.id);
        updateJob(updated);
        if (!isRankingAgentJobActive(updated.status)) {
          clearInterval(pollRef.current!);
        }
      } catch {
        // ignore transient
      }
    }, POLL_MS);
    return () => clearInterval(pollRef.current!);
  }, [job.id, job.status, updateJob]);

  async function handleApply() {
    setActionError(null);
    setApplying(true);
    try {
      const { job: updated } = await applyRankingAgentJob(job.id);
      updateJob(updated);
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Apply failed.");
    } finally {
      setApplying(false);
    }
  }

  async function handleCancel() {
    setActionError(null);
    try {
      updateJob(await cancelRankingAgentJob(job.id));
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Cancel failed.");
    }
  }

  async function handleRetry() {
    setActionError(null);
    try {
      updateJob(await retryRankingAgentJob(job.id));
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Retry failed.");
    }
  }

  const jobTypeIcon = {
    league_reset: <RotateCcw className="w-4 h-4" />,
    xp_event: <Zap className="w-4 h-4" />,
    achievement_batch: <Award className="w-4 h-4" />,
  }[job.job_type];

  const statusColor: Record<string, string> = {
    queued: "text-slate-600 bg-slate-100",
    calculating: "text-orange-600 bg-orange-50",
    validating: "text-orange-700 bg-orange-50",
    applying: "text-orange-700 bg-orange-100",
    preview_ready: "text-orange-700 bg-orange-50",
    completed: "text-orange-700 bg-orange-50",
    failed: "text-red-600 bg-red-50",
    cancelled: "text-slate-600 bg-slate-100",
  };

  return (
    <div className="fixed inset-y-0 right-0 w-[480px] bg-white shadow-2xl flex flex-col z-40 border-l border-slate-200 rounded-l-3xl">
      <div className="flex items-center justify-between px-5 py-4 border-b border-slate-100">
        <div className="flex items-center gap-2.5">
          <div className="w-9 h-9 rounded-2xl bg-orange-50 text-orange-600 flex items-center justify-center">
            <Trophy className="w-5 h-5" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="font-semibold text-slate-900 text-sm">
                {JOB_TYPE_LABELS[job.job_type]}
              </span>
              {jobTypeIcon}
            </div>
            <span className="text-xs text-slate-400">{job.id.slice(0, 8)}…</span>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <span
            className={`text-xs font-medium px-2.5 py-0.5 rounded-full ${statusColor[job.status] ?? "text-slate-600 bg-slate-100"}`}
          >
            {STATUS_LABELS[job.status] ?? job.status}
          </span>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-600 rounded-full p-1 hover:bg-slate-100">
            <X className="w-5 h-5" />
          </button>
        </div>
      </div>

      {isRankingAgentJobActive(job.status) && (
        <div className="px-5 pt-3">
          <div className="flex justify-between text-xs text-slate-500 mb-1">
            <span className="capitalize">{job.progress.stage}</span>
            <span>{job.progress.percent ?? 0}%</span>
          </div>
          <div className="h-2 bg-slate-100 rounded-full overflow-hidden">
            <div
              className="h-full bg-gradient-to-r from-orange-600 to-amber-500 rounded-full transition-all duration-500"
              style={{ width: `${job.progress.percent ?? 0}%` }}
            />
          </div>
        </div>
      )}

      <div className="flex-1 overflow-y-auto px-5 py-4 space-y-4">
        {(job.status === "calculating" || job.status === "validating") && (
          <div className="flex flex-col items-center gap-3 py-8 text-slate-400">
            <Clock className="w-8 h-8 animate-spin text-orange-600" />
            <p className="text-sm">
              {job.status === "calculating" ? "Calculating preview…" : "Validating results…"}
            </p>
          </div>
        )}

        {job.blocking_errors.length > 0 && (
          <div className="bg-red-50 border border-red-200 rounded-2xl p-3.5 space-y-1">
            <p className="text-xs font-semibold text-red-700 flex items-center gap-1">
              <XCircle className="w-3.5 h-3.5" /> Blocking errors
            </p>
            {job.blocking_errors.map((e, i) => (
              <p key={i} className="text-xs text-red-600">
                {e}
              </p>
            ))}
          </div>
        )}

        {job.warnings.length > 0 && (
          <div className="bg-amber-50 border border-amber-200 rounded-2xl p-3.5 space-y-1">
            <p className="text-xs font-semibold text-amber-700 flex items-center gap-1">
              <AlertTriangle className="w-3.5 h-3.5" /> Warnings
            </p>
            {job.warnings.map((w, i) => (
              <p key={i} className="text-xs text-amber-700">
                {w}
              </p>
            ))}
          </div>
        )}

        {job.artifact && job.status === "preview_ready" && (
          <div className="border border-slate-200 rounded-2xl overflow-hidden">
            <button
              onClick={() => setPreviewExpanded((v) => !v)}
              className="w-full flex items-center justify-between px-4 py-3 bg-slate-50 text-sm font-medium text-slate-700 hover:bg-slate-100"
            >
              <span>Preview</span>
              {previewExpanded ? (
                <ChevronUp className="w-4 h-4" />
              ) : (
                <ChevronDown className="w-4 h-4" />
              )}
            </button>
            {previewExpanded && (
              <div className="px-4 py-3 space-y-3">
                <PreviewSummary job={job} />
              </div>
            )}
          </div>
        )}

        {!!job.artifact?.ai_insights && (
          <div className="rounded-2xl border border-orange-200 bg-orange-50/70 px-4 py-3 space-y-1">
            <p className="text-xs font-semibold text-orange-700 flex items-center gap-1">
              <Brain className="w-3.5 h-3.5" /> AI Insight (Groq)
            </p>
            <p className="text-xs text-orange-950 leading-relaxed">
              {String(job.artifact.ai_insights)}
            </p>
          </div>
        )}

        {job.status === "completed" && (
          <div className="flex flex-col items-center gap-3 py-8 text-orange-600">
            <CheckCircle className="w-10 h-10" />
            <p className="text-sm font-medium">Job applied successfully</p>
            <CompletedSummary ids={job.created_entity_ids} />
          </div>
        )}

        {job.status === "failed" && (
          <div className="bg-red-50 border border-red-200 rounded-2xl p-4">
            <p className="text-sm font-medium text-red-700">Job failed</p>
            {job.error_message && (
              <p className="text-xs text-red-600 mt-1">{job.error_message}</p>
            )}
          </div>
        )}

        {actionError && (
          <p className="text-sm text-red-600 bg-red-50 rounded-2xl px-3 py-2">
            {actionError}
          </p>
        )}
      </div>

      <div className="px-5 py-4 border-t border-slate-100 flex justify-between gap-3">
        <div className="flex gap-2">
          {isRankingAgentJobActive(job.status) && job.status !== "applying" && (
            <button
              onClick={handleCancel}
              className="px-4 py-1.5 text-sm text-red-600 hover:text-red-700 border border-red-200 rounded-full hover:bg-red-50 transition-colors"
            >
              Cancel
            </button>
          )}
          {job.status === "failed" && (
            <button
              onClick={handleRetry}
              className="px-4 py-1.5 text-sm text-orange-600 border border-orange-200 rounded-full hover:bg-orange-50 transition-colors"
            >
              Retry
            </button>
          )}
        </div>
        {canApplyRankingAgentJob(job) && (
          <button
            onClick={handleApply}
            disabled={applying}
            className="px-5 py-2 text-sm bg-orange-600 text-white rounded-full hover:bg-orange-700 disabled:opacity-50 transition-colors font-medium"
          >
            {applying ? "Applying…" : "Apply to live DB"}
          </button>
        )}
      </div>
    </div>
  );
}

function PreviewSummary({ job }: { job: RankingAgentJob }) {
  const art = job.artifact!;

  if (job.job_type === "league_reset") {
    return (
      <div className="space-y-2 text-sm">
        <div className="grid grid-cols-3 gap-2">
          <Stat label="Total participants" value={String(art.total_participants ?? 0)} />
          <Stat
            label="Promotions"
            value={String((art.promotions as unknown[])?.length ?? 0)}
            color="text-orange-600"
          />
          <Stat
            label="Demotions"
            value={String((art.demotions as unknown[])?.length ?? 0)}
            color="text-red-500"
          />
        </div>
        <p className="text-xs text-slate-400">Week: {String(art.week ?? "")}</p>
      </div>
    );
  }

  if (job.job_type === "xp_event") {
    return (
      <div className="space-y-2 text-sm">
        <div className="grid grid-cols-2 gap-2">
          <Stat label="Users affected" value={String(art.target_user_count ?? 0)} />
          <Stat label="Estimated XP boost" value={String(art.estimated_total_xp_delta ?? "")} color="text-orange-600" />
        </div>
        <p className="text-xs text-slate-400">
          {String(art.multiplier ?? "")}× for {String(art.duration_hours ?? "")}h · expires{" "}
          {art.expires_at ? new Date(String(art.expires_at)).toLocaleString() : "—"}
        </p>
      </div>
    );
  }

  if (job.job_type === "achievement_batch") {
    const achievements = (art.achievements as Array<{
      slug: string; name: string; to_grant: number; already_unlocked: number;
    }>) ?? [];
    return (
      <div className="space-y-2 text-sm">
        <div className="grid grid-cols-2 gap-2">
          <Stat label="Users affected" value={String(art.total_users_affected ?? 0)} />
          <Stat label="Total XP to award" value={String(art.total_xp_to_award ?? 0)} color="text-orange-600" />
        </div>
        <div className="mt-2 divide-y text-xs">
          {achievements.map((a) => (
            <div key={a.slug} className="py-1.5 flex justify-between">
              <span className="font-mono text-slate-600">{a.slug}</span>
              <span className="text-slate-500">
                {a.to_grant} to grant · {a.already_unlocked} already unlocked
              </span>
            </div>
          ))}
        </div>
      </div>
    );
  }

  return (
    <pre className="text-xs text-slate-500 overflow-x-auto">
      {JSON.stringify(art, null, 2)}
    </pre>
  );
}

function Stat({
  label,
  value,
  color = "text-slate-900",
}: {
  label: string;
  value: string;
  color?: string;
}) {
  return (
    <div className="bg-slate-50 rounded-2xl p-2.5 border border-slate-100">
      <p className="text-xs text-slate-500">{label}</p>
      <p className={`text-lg font-bold ${color}`}>{value}</p>
    </div>
  );
}

function CompletedSummary({ ids }: { ids: Record<string, unknown> }) {
  if (!Object.keys(ids).length) return null;
  return (
    <div className="text-xs text-slate-600 bg-slate-50 rounded-2xl px-3.5 py-2.5 space-y-0.5 border border-slate-100">
      {Object.entries(ids).map(([k, v]) => (
        <div key={k}>
          <span className="font-medium">{k}: </span>
          <span>
            {Array.isArray(v)
              ? `${(v as unknown[]).length} records`
              : String(v)}
          </span>
        </div>
      ))}
    </div>
  );
}
