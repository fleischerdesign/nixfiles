import React, { useState, useEffect } from 'react';

export interface WorkspaceActionBannerProps {
  currentSessionId?: string;
  sessionNodeId?: string;
  workspaceUrn?: string;
  isDrifted?: boolean;
  driftFilesCount?: number;
  onExecuteRemote?: () => void;
  onSyncWorkspace?: () => void;
  onChatOnly?: () => void;
}

export function WorkspaceActionBanner({
  sessionNodeId,
  workspaceUrn: propUrn,
  isDrifted = false,
  driftFilesCount = 0,
  onExecuteRemote,
  onSyncWorkspace,
  onChatOnly
}: WorkspaceActionBannerProps) {
  const [dismissed, setDismissed] = useState(false);
  const [activeDrift, setActiveDrift] = useState(isDrifted);
  const [originNode, setOriginNode] = useState(sessionNodeId || '');
  const [resolvedUrn, setResolvedUrn] = useState(propUrn || '');
  const [syncing, setSyncing] = useState(false);
  const [syncStatus, setSyncStatus] = useState<{ success?: boolean; message?: string } | null>(null);

  // Query actual session drift state dynamically
  useEffect(() => {
    if (isDrifted) {
      setActiveDrift(true);
      return;
    }
    // Check if current session originated from a remote node
    fetch('/api/mesh/sessions')
      .then(res => res.ok ? res.json() : null)
      .then(data => {
        if (!data?.sessions || !Array.isArray(data.sessions)) return;
        const localNode = data.nodeId;
        const currentSession = data.sessions.find((s: any) => s.nodeId !== localNode && s.isLeaseActive);
        if (currentSession) {
          setOriginNode(currentSession.nodeId);
          if (currentSession.workspaceUrn) {
            setResolvedUrn(currentSession.workspaceUrn);
          }
          setActiveDrift(true);
        }
      })
      .catch(() => {});
  }, [isDrifted]);

  const handleSync = async () => {
    if (onSyncWorkspace) {
      onSyncWorkspace();
      return;
    }

    if (!resolvedUrn) {
      setSyncStatus({ success: false, message: 'Keine Workspace-Identität gefunden.' });
      return;
    }

    setSyncing(true);
    setSyncStatus(null);

    try {
      const res = await fetch('/api/mesh/workspace/sync', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workspaceUrn: resolvedUrn })
      });

      const data = await res.json();
      if (res.ok && data.success) {
        setSyncStatus({ success: true, message: data.message || 'Workspace erfolgreich synchronisiert!' });
        setTimeout(() => {
          setDismissed(true);
        }, 2000);
      } else {
        setSyncStatus({ success: false, message: data.message || data.error || 'Synchronisation fehlgeschlagen.' });
      }
    } catch (err: any) {
      setSyncStatus({ success: false, message: `Netzwerkfehler: ${err.message}` });
    } finally {
      setSyncing(false);
    }
  };

  if (dismissed || !activeDrift || !originNode) return null;

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: '8px',
        padding: '10px 14px',
        margin: '0 0 10px 0',
        borderRadius: '8px',
        backgroundColor: 'rgba(30, 41, 59, 0.75)',
        border: '1px solid rgba(59, 130, 246, 0.3)',
        backdropFilter: 'blur(8px)',
        fontSize: '12px',
        color: '#e2e8f0',
        animation: 'fadeIn 0.2s ease-in-out'
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontWeight: 500 }}>
          <span style={{ fontSize: '14px' }}>📍</span>
          <span>
            Projekt existiert primär auf <strong style={{ color: '#60a5fa' }}>{originNode}</strong>
            {driftFilesCount > 0 ? ` (${driftFilesCount} abweichende Dateien erkannt)` : ' (Auf diesem Gerät noch nicht synchron)'}
          </span>
        </div>
        <button
          type="button"
          onClick={() => setDismissed(true)}
          style={{
            background: 'none',
            border: 'none',
            color: '#94a3b8',
            cursor: 'pointer',
            fontSize: '12px',
            padding: '2px 4px'
          }}
          title="Schließen"
        >
          ✕
        </button>
      </div>

      {syncStatus && (
        <div
          style={{
            padding: '6px 10px',
            borderRadius: '5px',
            fontSize: '11px',
            backgroundColor: syncStatus.success ? 'rgba(16, 185, 129, 0.15)' : 'rgba(239, 68, 68, 0.15)',
            color: syncStatus.success ? '#34d399' : '#f87171',
            border: `1px solid ${syncStatus.success ? 'rgba(16, 185, 129, 0.3)' : 'rgba(239, 68, 68, 0.3)'}`
          }}
        >
          {syncStatus.message}
        </div>
      )}

      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap', marginTop: '2px' }}>
        <button
          type="button"
          onClick={onExecuteRemote}
          style={{
            padding: '4px 10px',
            borderRadius: '5px',
            backgroundColor: '#2563eb',
            border: '1px solid rgba(255, 255, 255, 0.15)',
            color: '#ffffff',
            fontWeight: 500,
            fontSize: '11px',
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            gap: '5px'
          }}
        >
          <span>🚀</span> Remote auf {originNode} (Alt+R)
        </button>

        <button
          type="button"
          onClick={handleSync}
          disabled={syncing}
          style={{
            padding: '4px 10px',
            borderRadius: '5px',
            backgroundColor: syncing ? 'rgba(255, 255, 255, 0.04)' : 'rgba(255, 255, 255, 0.08)',
            border: '1px solid rgba(255, 255, 255, 0.15)',
            color: syncing ? '#94a3b8' : '#e2e8f0',
            fontSize: '11px',
            cursor: syncing ? 'wait' : 'pointer',
            display: 'flex',
            alignItems: 'center',
            gap: '5px'
          }}
        >
          <span>{syncing ? '⏳' : '📥'}</span> {syncing ? 'Synchronisiere...' : 'Hierher synchronisieren'}
        </button>

        <button
          type="button"
          onClick={onChatOnly}
          style={{
            padding: '4px 10px',
            borderRadius: '5px',
            backgroundColor: 'transparent',
            border: '1px solid rgba(255, 255, 255, 0.1)',
            color: '#94a3b8',
            fontSize: '11px',
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            gap: '5px'
          }}
        >
          <span>💬</span> Nur Chatten (Kein Dateizugriff)
        </button>
      </div>
    </div>
  );
}

