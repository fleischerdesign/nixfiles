// Decide whether a same-agent spawn may inherit its parent's workspace source.
//
// A repository session (`sessions.create` with `repository: { url }`) keeps its
// checkout on the session runner. The Gateway holds only the publication donor:
// no origin, no working tree and no accepted checkpoint bytes. Inheritance would
// therefore fall through to the agent workspace, which is an unrelated
// repository — `git ls-remote origin` fails there, and a workspace that happened
// to have a remote would silently produce a worktree of the wrong repository.
//
// Only a parent with its own managed worktree or a registered project can supply
// a child worktree on the Gateway. Everything else keeps upstream resolution.
//
// The module is installed next to the dist bundle and called from
// `prepareSessionWorktreeCreation`; the check exercises this table against the
// built artifact so a decision change is visible without booting a Gateway.
export function parentSpawnSourceRefusal(entry) {
  if (!entry || typeof entry !== "object") return undefined;
  if (entry.worktree || entry.pendingWorktree) return undefined;

  if (typeof entry.projectId === "string" && entry.projectId.trim()) return undefined;
  const repositoryWorkspaceId =
    typeof entry.repositoryWorkspaceId === "string" ? entry.repositoryWorkspaceId.trim() : "";
  if (!repositoryWorkspaceId) return undefined;

  return (
    "Subagent spawn cannot inherit this session's repository: its checkout exists only on the " +
    "session's paired node, while a managed child worktree is created on the Gateway. Open the " +
    "repository as a Gateway project and spawn there, or run the work in this session."
  );
}
