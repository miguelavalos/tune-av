import { createFileRoute } from "@tanstack/react-router";
import { ProtectedRoute } from "@/components/protected-route";
import { TuneAppShell } from "@/components/tune-app-shell";
import { TuneListen } from "@/components/tune-listen";

export const Route = createFileRoute("/listen")({
  component: ListenRoute
});

function ListenRoute() {
  return (
    <ProtectedRoute>
      <TuneAppShell>
        <TuneListen />
      </TuneAppShell>
    </ProtectedRoute>
  );
}
