import React from "react";
import { useLocation } from "react-router-dom";
import { useI18n } from "../lib/i18n";
import { EmptyState } from "./EmptyState";

type Labels = { title: string; description: string; retry: string };

type Props = { labels: Labels; children: React.ReactNode };
type State = { error: Error | null };

class Boundary extends React.Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    console.error("Admin page crashed", error, info.componentStack);
  }

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;
    const { labels } = this.props;
    return (
      <div role="alert">
        <EmptyState
          title={labels.title}
          description={`${labels.description} (${error.message})`}
          action={
            <button className="primary-button" onClick={() => this.setState({ error: null })}>
              {labels.retry}
            </button>
          }
        />
      </div>
    );
  }
}

/** Wraps the routed page only, so the sidebar and topbar keep working; navigating away clears the error. */
export const RouteErrorBoundary = ({ children }: { children: React.ReactNode }) => {
  const { t } = useI18n();
  const { pathname } = useLocation();
  return (
    <Boundary key={pathname} labels={t.routeError}>
      {children}
    </Boundary>
  );
};
