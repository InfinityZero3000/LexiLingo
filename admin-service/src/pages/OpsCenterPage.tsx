import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { StatusPill } from "../components/StatusPill";
import { DataTable, Column } from "../components/DataTable";
import { EmptyState } from "../components/EmptyState";
import { TableSkeleton } from "../components/Skeleton";
import { useAuth } from "../components/AuthProvider";
import { useConfirm } from "../components/ConfirmDialog";
import {
  getBackupOverview,
  getCeleryOverview,
  getContentAgentOverview,
  getIntegrationHealth,
  getProductEventOverview,
  getQuotaUsage,
  getReminderOverview,
  resetQuota,
  IntegrationResult,
  QuotaUsage,
  ScheduledTask,
} from "../lib/opsApi";
import { useI18n } from "../lib/i18n";

type Tone = "success" | "warning" | "info" | "danger" | "neutral";

const INTEGRATION_TONE: Record<string, Tone> = { ok: "success", dead: "danger", unreachable: "danger", not_configured: "neutral" };
const QUOTA_TONE: Record<string, Tone> = { normal: "success", warning: "warning", critical: "danger", blocked: "danger" };
const STATUS_COLORS: Record<string, string> = {
  sent: "var(--accent-2)",
  dry_run: "var(--accent-3)",
  skipped: "var(--muted)",
  failed: "var(--accent)",
};

const TASK_TONE: Record<string, Tone> = { ok: "success", stale: "warning", failed: "danger", never: "neutral" };
const BACKUP_TONE: Record<string, Tone> = { ok: "success", stale: "warning", failed: "danger", never: "neutral", unavailable: "neutral" };

const formatAge = (seconds: number | null | undefined) => {
  if (seconds == null) return "—";
  if (seconds < 3600) return `${Math.max(Math.round(seconds / 60), 0)} min`;
  if (seconds < 172800) return `${Math.round(seconds / 3600)} h`;
  return `${Math.round(seconds / 86400)} d`;
};
const formatMb = (bytes?: number) => (bytes == null ? "—" : `${(bytes / 1048576).toFixed(1)} MB`);

const messageOf = (err: unknown, fallback: string) => (err instanceof Error && err.message ? err.message : fallback);

const Section = ({ title, description, action, children }: {
  title: string; description?: string; action?: React.ReactNode; children: React.ReactNode;
}) => (
  <section className="panel stack" aria-label={title}>
    <div className="cluster cluster--between">
      <div>
        <h2>{title}</h2>
        {description && <p className="text-muted">{description}</p>}
      </div>
      {action}
    </div>
    {children}
  </section>
);

export const OpsCenterPage = () => {
  const { t } = useI18n();
  const { role } = useAuth();
  const confirm = useConfirm();
  const queryClient = useQueryClient();
  const [days, setDays] = useState(14);

  // Probes make real outbound calls, so they run only on request.
  const integrations = useQuery({ queryKey: ["ops-integrations"], queryFn: getIntegrationHealth, enabled: false });
  const quotas = useQuery({ queryKey: ["ops-quotas"], queryFn: getQuotaUsage });
  const reminders = useQuery({ queryKey: ["ops-reminders", days], queryFn: () => getReminderOverview(days) });
  const events = useQuery({ queryKey: ["ops-events", days], queryFn: () => getProductEventOverview(days) });
  const agent = useQuery({ queryKey: ["ops-content-agent"], queryFn: getContentAgentOverview });
  const celery = useQuery({ queryKey: ["ops-celery"], queryFn: getCeleryOverview, refetchInterval: 30_000 });
  const backups = useQuery({ queryKey: ["ops-backups"], queryFn: getBackupOverview, refetchInterval: 60_000 });

  const [resetError, setResetError] = useState<string | null>(null);
  const reset = useMutation({
    mutationFn: (api: string) => resetQuota(api), // react-query would pass its own context as a 2nd argument
    onMutate: () => setResetError(null),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["ops-quotas"] }),
    onError: (err) => setResetError(messageOf(err, t.ops.resetFailed)),
  });

  const askReset = async (api: string) => {
    const ok = await confirm({
      title: t.ops.resetTitle,
      message: t.ops.resetMessage.replace("{api}", api),
      confirmLabel: t.ops.reset,
      danger: true,
    });
    if (ok) reset.mutate(api);
  };

  const taskColumns: Column<ScheduledTask>[] = [
    { header: t.ops.taskName, render: (x) => <strong>{x.name}</strong> },
    { header: t.ops.schedule, render: (x) => <span className="text-small">{x.schedule}</span> },
    { header: t.ops.state, render: (x) => <StatusPill tone={TASK_TONE[x.status]} label={t.ops.taskStates[x.status]} /> },
    { header: t.ops.lastRun, render: (x) => (x.last_run_at ? new Date(x.last_run_at).toLocaleString() : "—") },
    { header: t.ops.detail, render: (x) => (x.error ? <span className="text-danger text-small">{x.error}</span> : x.runtime != null ? `${x.runtime}s` : "—") },
  ];

  const integrationColumns: Column<IntegrationResult>[] = [
    { header: t.ops.integration, render: (r) => <strong>{r.integration}</strong> },
    { header: t.ops.feature, render: (r) => r.feature },
    { header: t.ops.state, render: (r) => <StatusPill tone={INTEGRATION_TONE[r.state] ?? "neutral"} label={t.ops.integrationStates[r.state] ?? r.state} /> },
    { header: t.ops.detail, render: (r) => r.detail || <span className="mono text-small">{r.env_var}</span> },
  ];

  const quotaColumns: Column<QuotaUsage>[] = [
    { header: t.ops.api, render: (q) => <strong>{q.api}</strong> },
    {
      header: t.ops.usage,
      render: (q) => (
        <div className="quota">
          <div className="quota__bar" role="progressbar" aria-valuenow={Math.round(q.usage_percent)} aria-valuemin={0} aria-valuemax={100} aria-label={q.api}>
            <div className={`quota__fill quota__fill--${q.status}`} style={{ width: `${Math.min(q.usage_percent, 100)}%` }} />
          </div>
          <span className="text-small">{q.used.toLocaleString()} / {q.budget.toLocaleString()} ({q.usage_percent}%)</span>
        </div>
      ),
    },
    { header: t.ops.state, render: (q) => <StatusPill tone={QUOTA_TONE[q.status] ?? "neutral"} label={t.ops.quotaStates[q.status] ?? q.status} /> },
    ...(role === "super_admin"
      ? [{
          header: t.common.actions,
          render: (q: QuotaUsage) => (
            <button className="ghost-button small danger" onClick={() => askReset(q.api)} disabled={reset.isPending}>
              {t.ops.reset}
            </button>
          ),
        }]
      : []),
  ];

  const r = reminders.data;
  const totals = r?.totals ?? {};

  return (
    <div className="stack">
      <SectionHeader
        title={t.ops.title}
        description={t.ops.description}
        action={
          <label className="filter-date">
            <span>{t.ops.window}</span>
            <select className="filter-select" value={days} onChange={(e) => setDays(Number(e.target.value))}>
              {[7, 14, 30].map((d) => <option key={d} value={d}>{d} {t.ops.days}</option>)}
            </select>
          </label>
        }
      />

      <Section
        title={t.ops.integrationsTitle}
        description={t.ops.integrationsHint}
        action={
          <button className="primary-button" onClick={() => integrations.refetch()} disabled={integrations.isFetching}>
            {integrations.isFetching ? t.ops.checking : t.ops.checkNow}
          </button>
        }
      >
        {integrations.error && <div className="form-error" role="alert">{messageOf(integrations.error, t.ops.loadFailed)}</div>}
        {integrations.data ? (
          <>
            <StatusPill
              tone={integrations.data.healthy ? "success" : "danger"}
              label={integrations.data.healthy ? t.ops.allHealthy : t.ops.brokenCount.replace("{n}", String(integrations.data.broken))}
            />
            <DataTable columns={integrationColumns} rows={integrations.data.integrations} rowKey={(x) => x.integration} />
          </>
        ) : (
          !integrations.error && <p className="text-muted">{t.ops.notChecked}</p>
        )}
      </Section>

      <Section title={t.ops.quotasTitle} description={t.ops.quotasHint}>
        {resetError && <div className="form-error" role="alert">{resetError}</div>}
        {quotas.error && <div className="form-error" role="alert">{messageOf(quotas.error, t.ops.loadFailed)}</div>}
        {quotas.isLoading ? <TableSkeleton rows={4} cols={4} /> : (
          <DataTable columns={quotaColumns} rows={quotas.data?.apis ?? []} rowKey={(q) => q.api} />
        )}
        {quotas.data && <p className="text-small text-muted">{t.ops.resetsIn.replace("{time}", quotas.data.reset_in)}</p>}
      </Section>

      <Section
        title={t.ops.remindersTitle}
        description={t.ops.remindersHint}
        action={
          r && (
            <div className="cluster">
              <StatusPill tone={r.enabled ? "success" : "neutral"} label={r.enabled ? t.ops.remindersOn : t.ops.remindersOff} />
              {r.enabled && r.dry_run && <StatusPill tone="warning" label={t.ops.dryRun} />}
            </div>
          )
        }
      >
        {reminders.error && <div className="form-error" role="alert">{messageOf(reminders.error, t.ops.loadFailed)}</div>}
        <div className="card-grid">
          {["sent", "dry_run", "skipped", "failed"].map((status) => (
            <StatCard key={status} label={t.ops.reminderStatus[status] ?? status} value={String(totals[status] ?? 0)} loading={reminders.isLoading} accent={status === "failed" ? "berry" : status === "sent" ? "teal" : "ink"} />
          ))}
        </div>
        {r && r.by_day.length > 0 ? (
          <div className="chart-container">
            <ResponsiveContainer width="100%" height={260}>
              <BarChart data={r.by_day} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--line)" />
                <XAxis dataKey="date" tick={{ fontSize: 12 }} />
                <YAxis allowDecimals={false} tick={{ fontSize: 12 }} />
                <Tooltip />
                <Legend />
                {Object.keys(STATUS_COLORS).map((status) => (
                  <Bar key={status} dataKey={status} stackId="a" fill={STATUS_COLORS[status]} name={t.ops.reminderStatus[status] ?? status} />
                ))}
              </BarChart>
            </ResponsiveContainer>
          </div>
        ) : (
          !reminders.isLoading && <EmptyState title={t.ops.noReminders} description={t.ops.noRemindersHint} />
        )}
      </Section>

      <Section title={t.ops.eventsTitle} description={`${(events.data?.total ?? 0).toLocaleString()} ${t.ops.eventsTotal}`}>
        {events.error && <div className="form-error" role="alert">{messageOf(events.error, t.ops.loadFailed)}</div>}
        {events.isLoading ? <TableSkeleton rows={5} cols={3} /> : (events.data?.events.length ?? 0) === 0 ? (
          <EmptyState title={t.ops.noEvents} />
        ) : (
          <DataTable
            columns={[
              { header: t.ops.eventName, render: (e) => <span className="mono">{e.event_name}</span> },
              { header: t.ops.count, align: "right", render: (e) => e.count.toLocaleString(), sortValue: (e) => e.count },
              { header: t.ops.lastSeen, render: (e) => (e.last_at ? new Date(e.last_at).toLocaleString() : "—") },
            ]}
            rows={events.data!.events}
            rowKey={(e) => e.event_name}
          />
        )}
      </Section>

      <Section title={t.ops.celeryTitle} description={t.ops.celeryHint}>
        {celery.error && <div className="form-error" role="alert">{messageOf(celery.error, t.ops.loadFailed)}</div>}
        {celery.data && (
          <>
            <div className="cluster">
              <StatusPill
                tone={celery.data.worker.online ? "success" : "danger"}
                label={`${t.ops.worker}: ${celery.data.worker.online ? t.ops.online : celery.data.worker.reachable ? t.ops.noWorker : t.ops.unknown}`}
              />
              <StatusPill tone={celery.data.beat_alive ? "success" : "danger"} label={`${t.ops.beat}: ${celery.data.beat_alive ? t.ops.online : t.ops.noBeat}`} />
              <StatusPill
                tone={celery.data.reminders_enabled ? "success" : "neutral"}
                label={`${t.ops.remindersFlag}: ${celery.data.reminders_enabled ? t.common.enabled : t.common.disabled}`}
              />
              {celery.data.queue_depth != null && <StatusPill tone={celery.data.queue_depth > 100 ? "warning" : "neutral"} label={`${t.ops.queueDepth}: ${celery.data.queue_depth}`} />}
            </div>
            <DataTable columns={taskColumns} rows={celery.data.tasks} rowKey={(x) => x.name} />
          </>
        )}
      </Section>

      <Section title={t.ops.backupTitle} description={t.ops.backupHint}>
        {backups.error && <div className="form-error" role="alert">{messageOf(backups.error, t.ops.loadFailed)}</div>}
        {backups.data && (
          <>
            <div className="cluster">
              <StatusPill tone={BACKUP_TONE[backups.data.state]} label={`${t.ops.backupLatest}: ${t.ops.backupStates[backups.data.state]}`} />
              <StatusPill tone={BACKUP_TONE[backups.data.verify.state]} label={`${t.ops.backupVerify}: ${t.ops.backupStates[backups.data.verify.state]}`} />
              {backups.data.backup && (
                <StatusPill tone={backups.data.backup.offsite ? "success" : "warning"} label={backups.data.backup.offsite ? t.ops.offsiteYes : t.ops.offsiteNo} />
              )}
            </div>
            {backups.data.state === "unavailable" && <p className="text-muted">{t.ops.backupUnavailable}</p>}
            {backups.data.failure_marker_at && (
              <div className="form-error" role="alert">{t.ops.backupFailureMarker.replace("{at}", new Date(backups.data.failure_marker_at).toLocaleString())}</div>
            )}
            {backups.data.backup && (
              <table className="kv-table">
                <tbody>
                  <tr><td className="kv-label">{t.ops.backupAge}</td><td className="kv-value">{formatAge(backups.data.backup.age_seconds)}</td></tr>
                  <tr><td className="kv-label">PostgreSQL</td><td className="kv-value">{formatMb(backups.data.backup.postgres_bytes)}</td></tr>
                  <tr><td className="kv-label">MongoDB</td><td className="kv-value">{formatMb(backups.data.backup.mongo_bytes)}</td></tr>
                  <tr><td className="kv-label">{t.ops.backupSets}</td><td className="kv-value">{backups.data.backup.sets_kept ?? "—"}</td></tr>
                  {backups.data.backup.error && <tr><td className="kv-label">{t.ops.detail}</td><td className="kv-value text-danger">{backups.data.backup.error}</td></tr>}
                  {backups.data.verify.at && <tr><td className="kv-label">{t.ops.backupVerify}</td><td className="kv-value">{formatAge(backups.data.verify.age_seconds)}</td></tr>}
                </tbody>
              </table>
            )}
          </>
        )}
      </Section>

      <Section title={t.ops.agentTitle} description={t.ops.agentHint}>
        {agent.error && <div className="form-error" role="alert">{messageOf(agent.error, t.ops.loadFailed)}</div>}
        <div className="cluster">
          {Object.entries(agent.data?.by_status ?? {}).map(([status, count]) => (
            <StatusPill key={status} tone={status.includes("fail") ? "danger" : "neutral"} label={`${status}: ${count}`} />
          ))}
          {agent.data && Object.keys(agent.data.by_status).length === 0 && <span className="text-muted">{t.ops.noJobs}</span>}
        </div>
        {(agent.data?.recent_failures ?? []).map((f) => (
          <div key={f.id} className="form-error">
            <span className="mono text-small">{f.id.slice(0, 8)}</span> · {f.error}
          </div>
        ))}
      </Section>
    </div>
  );
};
