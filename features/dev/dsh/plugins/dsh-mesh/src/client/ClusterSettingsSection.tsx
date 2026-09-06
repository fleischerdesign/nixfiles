import React, { useState, useEffect } from 'react';
import type { ClusterSettingsKey } from './locales.js';

interface PeerItem {
  id: string;
  endpoint: string;
  lastHeartbeatMs: number;
  rttMs: number;
  healthy: boolean;
  maxTxSeen: number;
  scope: 'system' | 'user' | 'group';
  owner?: string;
  group?: string;
  dynamic: boolean;
}

interface RemoteSessionItem {
  sessionId: string;
  workspaceUrn: string;
  workspaceLabel?: string;
  workspaceType?: 'git' | 'relhome' | 'raw';
  nodeId: string;
  lastTurnSeq: number;
  updatedAt: number;
  leaseEpoch: number;
  leaseHolder: string;
  isLeaseActive: boolean;
}

export interface ClusterSectionProps {
  close?: () => void;
  t?: (key: ClusterSettingsKey) => string;
}

export function ClusterSettingsSection({ t = (k: string) => k }: ClusterSectionProps) {
  const [activeTab, setActiveTab] = useState<'nodes' | 'sessions'>('nodes');
  const [peers, setPeers] = useState<PeerItem[]>([]);
  const [sessions, setSessions] = useState<RemoteSessionItem[]>([]);
  const [localNodeId, setLocalNodeId] = useState<string>('standalone');
  const [loading, setLoading] = useState(true);

  // Add node form state
  const [showAddForm, setShowAddForm] = useState(false);
  const [newNodeId, setNewNodeId] = useState('');
  const [newEndpoint, setNewEndpoint] = useState('');
  const [newScope, setNewScope] = useState<'user' | 'group'>('user');
  const [newGroup, setNewGroup] = useState('');
  const [adding, setAdding] = useState(false);
  const [addError, setAddError] = useState<string | null>(null);

  const fetchPeers = async () => {
    setLoading(true);
    try {
      const res = await fetch('/api/mesh/peers');
      if (res.ok) {
        const data = await res.json();
        setLocalNodeId(data.nodeId || 'standalone');
        setPeers(data.peers || []);
      }
    } catch {
      // Offline / network failure
    } finally {
      setLoading(false);
    }
  };

  const fetchSessions = async () => {
    try {
      const res = await fetch('/api/mesh/sessions');
      if (res.ok) {
        const data = await res.json();
        setSessions(data.sessions || []);
      }
    } catch {
      // Offline / network failure
    }
  };

  useEffect(() => {
    fetchPeers();
    fetchSessions();
  }, []);

  const handleClaimSession = async (sessionId: string, holderNodeId: string) => {
    try {
      const res = await fetch('/mesh/lease/handoff', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sessionId,
          requestingNodeId: localNodeId,
          currentEpoch: 1,
          force: true
        })
      });
      if (res.ok) {
        fetchSessions();
      }
    } catch {
      // Ignore failure
    }
  };

  const handleAddPeer = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newNodeId || !newEndpoint) return;
    if (newScope === 'group' && !newGroup.trim()) return;

    setAdding(true);
    setAddError(null);

    try {
      const payload: any = {
        id: newNodeId.trim(),
        endpoint: newEndpoint.trim(),
        scope: newScope,
      };
      if (newScope === 'group') {
        payload.group = newGroup.trim();
      }

      const res = await fetch('/api/mesh/peers', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });

      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to add node');
      }

      setNewNodeId('');
      setNewEndpoint('');
      setNewGroup('');
      setShowAddForm(false);
      fetchPeers();
    } catch (err: any) {
      setAddError(err.message);
    } finally {
      setAdding(false);
    }
  };

  const handleDeletePeer = async (peerId: string) => {
    try {
      const res = await fetch(`/api/mesh/peers?id=${encodeURIComponent(peerId)}`, {
        method: 'DELETE',
      });
      if (res.ok) {
        fetchPeers();
      }
    } catch {
      // Ignore failure
    }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', maxWidth: '780px' }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: '12px' }}>
        <div>
          <h3 style={{ margin: '0 0 4px 0', fontSize: '15px', fontWeight: 600, color: 'var(--dsw-alias-label-primary, #fff)' }}>
            {t('settings.cluster.title')}
          </h3>
          <p style={{ margin: 0, fontSize: '12px', color: 'var(--dsw-alias-label-tertiary, #9ca3af)' }}>
            {t('settings.cluster.description')}
          </p>
          <div style={{ display: 'flex', gap: '8px', marginTop: '10px' }}>
            <button
              type="button"
              onClick={() => setActiveTab('nodes')}
              style={{
                padding: '4px 10px',
                borderRadius: '5px',
                backgroundColor: activeTab === 'nodes' ? '#2563eb' : 'rgba(255, 255, 255, 0.08)',
                border: 'none',
                color: '#fff',
                fontSize: '11px',
                fontWeight: 500,
                cursor: 'pointer'
              }}
            >
              {t('settings.cluster.tabNodes')}
            </button>
            <button
              type="button"
              onClick={() => { setActiveTab('sessions'); fetchSessions(); }}
              style={{
                padding: '4px 10px',
                borderRadius: '5px',
                backgroundColor: activeTab === 'sessions' ? '#2563eb' : 'rgba(255, 255, 255, 0.08)',
                border: 'none',
                color: '#fff',
                fontSize: '11px',
                fontWeight: 500,
                cursor: 'pointer'
              }}
            >
              {t('settings.cluster.tabSessions')} ({sessions.length})
            </button>
          </div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <button
            type="button"
            onClick={() => { setShowAddForm(!showAddForm); setAddError(null); }}
            style={{
              padding: '5px 12px',
              borderRadius: '6px',
              backgroundColor: showAddForm ? 'rgba(255, 255, 255, 0.16)' : 'rgba(255, 255, 255, 0.08)',
              border: '1px solid rgba(255, 255, 255, 0.12)',
              color: 'var(--dsw-alias-label-primary, #fff)',
              fontSize: '12px',
              cursor: 'pointer',
            }}
          >
            {t('settings.cluster.addNode')}
          </button>
          <button
            type="button"
            onClick={fetchPeers}
            style={{
              padding: '5px 12px',
              borderRadius: '6px',
              backgroundColor: 'rgba(255, 255, 255, 0.08)',
              border: '1px solid rgba(255, 255, 255, 0.12)',
              color: 'var(--dsw-alias-label-primary, #fff)',
              fontSize: '12px',
              cursor: 'pointer',
            }}
          >
            {t('settings.cluster.refresh')}
          </button>
        </div>
      </div>

      {/* Add Node Form */}
      {showAddForm && (
        <form
          onSubmit={handleAddPeer}
          style={{
            display: 'flex',
            flexDirection: 'column',
            gap: '12px',
            padding: '16px',
            borderRadius: '8px',
            backgroundColor: 'var(--dsw-alias-bg-secondary, rgba(255, 255, 255, 0.04))',
            border: '1px solid var(--dsw-alias-border-secondary, rgba(255, 255, 255, 0.1))',
          }}
        >
          <div style={{ display: 'grid', gridTemplateColumns: '1.2fr 1.5fr 1fr 1fr', gap: '10px', alignItems: 'center' }}>
            <input
              type="text"
              value={newNodeId}
              onChange={e => setNewNodeId(e.target.value)}
              placeholder={t('settings.cluster.nodeIdPlaceholder')}
              required
              style={{
                padding: '7px 10px',
                borderRadius: '6px',
                backgroundColor: 'rgba(0, 0, 0, 0.25)',
                border: '1px solid rgba(255, 255, 255, 0.12)',
                color: '#fff',
                fontSize: '12px',
                outline: 'none',
              }}
            />
            <input
              type="text"
              value={newEndpoint}
              onChange={e => setNewEndpoint(e.target.value)}
              placeholder={t('settings.cluster.endpointPlaceholder')}
              required
              style={{
                padding: '7px 10px',
                borderRadius: '6px',
                backgroundColor: 'rgba(0, 0, 0, 0.25)',
                border: '1px solid rgba(255, 255, 255, 0.12)',
                color: '#fff',
                fontSize: '12px',
                outline: 'none',
              }}
            />
            <select
              value={newScope}
              onChange={e => setNewScope(e.target.value as any)}
              style={{
                padding: '7px 10px',
                borderRadius: '6px',
                backgroundColor: 'rgba(0, 0, 0, 0.25)',
                border: '1px solid rgba(255, 255, 255, 0.12)',
                color: '#fff',
                fontSize: '12px',
                outline: 'none',
              }}
            >
              <option value="user">{t('settings.cluster.scopeUser')}</option>
              <option value="group">{t('settings.cluster.scopeGroup')}</option>
            </select>
            {newScope === 'group' ? (
              <input
                type="text"
                value={newGroup}
                onChange={e => setNewGroup(e.target.value)}
                placeholder={t('settings.cluster.groupPlaceholder')}
                required
                style={{
                  padding: '7px 10px',
                  borderRadius: '6px',
                  backgroundColor: 'rgba(0, 0, 0, 0.25)',
                  border: '1px solid rgba(255, 255, 255, 0.12)',
                  color: '#fff',
                  fontSize: '12px',
                  outline: 'none',
                }}
              />
            ) : <div />}
          </div>

          {addError && (
            <div style={{ fontSize: '11px', color: '#f87171' }}>
              {addError}
            </div>
          )}

          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '8px' }}>
            <button
              type="button"
              onClick={() => setShowAddForm(false)}
              style={{
                padding: '4px 10px',
                borderRadius: '5px',
                backgroundColor: 'transparent',
                border: '1px solid rgba(255, 255, 255, 0.1)',
                color: '#9ca3af',
                fontSize: '11px',
                cursor: 'pointer',
              }}
            >
              {t('settings.cluster.cancel')}
            </button>
            <button
              type="submit"
              disabled={adding}
              style={{
                padding: '4px 12px',
                borderRadius: '5px',
                backgroundColor: '#3b82f6',
                border: 'none',
                color: '#fff',
                fontSize: '11px',
                fontWeight: 600,
                cursor: adding ? 'wait' : 'pointer',
              }}
            >
              {adding ? t('settings.cluster.loading') : t('settings.cluster.save')}
            </button>
          </div>
        </form>
      )}

      {/* Local Node Status */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '12px 16px',
          borderRadius: '8px',
          backgroundColor: 'var(--dsw-alias-bg-secondary, rgba(255, 255, 255, 0.03))',
          border: '1px solid var(--dsw-alias-border-secondary, rgba(255, 255, 255, 0.08))',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <span
            style={{
              width: '8px',
              height: '8px',
              borderRadius: '50%',
              backgroundColor: '#10b981',
              display: 'inline-block',
            }}
          />
          <span style={{ fontSize: '13px', fontWeight: 500 }}>{t('settings.cluster.localNode')}</span>
        </div>
        <span style={{ fontSize: '13px', fontFamily: 'monospace', fontWeight: 600, color: '#60a5fa' }}>
          {localNodeId}
        </span>
      </div>

      {/* Tab 1: Peer Nodes Table */}
      {activeTab === 'nodes' && (
        loading ? (
          <div style={{ fontSize: '12px', color: 'var(--dsw-alias-label-tertiary, #9ca3af)', padding: '20px 0' }}>
            {t('settings.cluster.loading')}
          </div>
        ) : peers.length === 0 ? (
          <div style={{ fontSize: '12px', color: 'var(--dsw-alias-label-tertiary, #9ca3af)', padding: '20px 0' }}>
            {t('settings.cluster.empty')}
          </div>
        ) : (
          <div
            style={{
              display: 'flex',
              flexDirection: 'column',
              borderRadius: '8px',
              backgroundColor: 'rgba(255, 255, 255, 0.02)',
              border: '1px solid rgba(255, 255, 255, 0.08)',
              overflow: 'hidden',
            }}
          >
            <div
              style={{
                display: 'grid',
                gridTemplateColumns: '2fr 2.5fr 1.5fr 1.2fr 1.4fr',
                padding: '8px 12px',
                backgroundColor: 'rgba(255, 255, 255, 0.04)',
                borderBottom: '1px solid rgba(255, 255, 255, 0.06)',
                fontSize: '11px',
                fontWeight: 600,
                color: 'var(--dsw-alias-label-secondary, #d1d5db)',
              }}
            >
              <div>{t('settings.cluster.colNode')}</div>
              <div>{t('settings.cluster.colEndpoint')}</div>
              <div>{t('settings.cluster.colScope')}</div>
              <div>{t('settings.cluster.colLatency')}</div>
              <div style={{ textAlign: 'right' }}>{t('settings.cluster.colStatus')}</div>
            </div>

            <div style={{ maxHeight: '360px', overflowY: 'auto' }}>
              {peers.map((peer, idx) => (
                <div
                  key={peer.id || idx}
                  style={{
                    display: 'grid',
                    gridTemplateColumns: '2fr 2.5fr 1.5fr 1.2fr 1.4fr',
                    padding: '10px 12px',
                    borderBottom: idx === peers.length - 1 ? 'none' : '1px solid rgba(255, 255, 255, 0.04)',
                    fontSize: '11px',
                    fontFamily: 'monospace',
                    alignItems: 'center',
                  }}
                >
                  <div style={{ fontWeight: 600, color: '#60a5fa' }}>{peer.id}</div>
                  <div style={{ opacity: 0.85, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {peer.endpoint}
                  </div>
                  <div>
                    <span
                      style={{
                        padding: '2px 6px',
                        borderRadius: '4px',
                        backgroundColor:
                          peer.scope === 'system' ? 'rgba(99, 102, 241, 0.15)' :
                          peer.scope === 'group' ? 'rgba(168, 85, 247, 0.15)' :
                          'rgba(59, 130, 246, 0.15)',
                        color:
                          peer.scope === 'system' ? '#818cf8' :
                          peer.scope === 'group' ? '#c084fc' :
                          '#60a5fa',
                        fontSize: '10px',
                      }}
                      title={peer.group ? `Group: ${peer.group}` : (peer.owner ? `Owner: ${peer.owner}` : undefined)}
                    >
                      {peer.scope === 'system' ? t('settings.cluster.scopeSystem') :
                       peer.scope === 'group' ? `${t('settings.cluster.scopeGroup')}:${peer.group}` :
                       t('settings.cluster.scopeUser')}
                    </span>
                  </div>
                  <div style={{ opacity: 0.85 }}>
                    {peer.rttMs >= 0 ? `${peer.rttMs} ms` : '—'}
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: '8px' }}>
                    <span
                      style={{
                        padding: '2px 7px',
                        borderRadius: '4px',
                        backgroundColor: peer.healthy ? 'rgba(16, 185, 129, 0.15)' : 'rgba(239, 68, 68, 0.15)',
                        color: peer.healthy ? '#34d399' : '#f87171',
                        fontSize: '10px',
                        fontWeight: 600,
                      }}
                    >
                      {peer.healthy ? t('settings.cluster.healthy') : t('settings.cluster.unreachable')}
                    </span>
                    {peer.dynamic && (
                      <button
                        type="button"
                        onClick={() => handleDeletePeer(peer.id)}
                        title={t('settings.cluster.delete')}
                        style={{
                          padding: '2px 6px',
                          borderRadius: '4px',
                          backgroundColor: 'rgba(239, 68, 68, 0.1)',
                          border: '1px solid rgba(239, 68, 68, 0.2)',
                          color: '#f87171',
                          fontSize: '10px',
                          cursor: 'pointer',
                        }}
                      >
                        ✕
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )
      )}

      {/* Tab 2: Distributed Sessions Table */}
      {activeTab === 'sessions' && (
        sessions.length === 0 ? (
          <div style={{ fontSize: '12px', color: 'var(--dsw-alias-label-tertiary, #9ca3af)', padding: '20px 0' }}>
            {t('settings.cluster.sessionsEmpty')}
          </div>
        ) : (
          <div
            style={{
              display: 'flex',
              flexDirection: 'column',
              borderRadius: '8px',
              backgroundColor: 'rgba(255, 255, 255, 0.02)',
              border: '1px solid rgba(255, 255, 255, 0.08)',
              overflow: 'hidden',
            }}
          >
            <div
              style={{
                display: 'grid',
                gridTemplateColumns: '2fr 3fr 1.5fr 1.2fr',
                padding: '8px 12px',
                backgroundColor: 'rgba(255, 255, 255, 0.04)',
                borderBottom: '1px solid rgba(255, 255, 255, 0.06)',
                fontSize: '11px',
                fontWeight: 600,
                color: 'var(--dsw-alias-label-secondary, #d1d5db)',
              }}
            >
              <div>{t('settings.cluster.colSession')}</div>
              <div>{t('settings.cluster.colWorkspace')}</div>
              <div>{t('settings.cluster.colLease')}</div>
              <div style={{ textAlign: 'right' }}>Aktion</div>
            </div>

            <div style={{ maxHeight: '360px', overflowY: 'auto' }}>
              {sessions.map((s, idx) => (
                <div
                  key={s.sessionId || idx}
                  style={{
                    display: 'grid',
                    gridTemplateColumns: '2fr 3fr 1.5fr 1.2fr',
                    padding: '10px 12px',
                    borderBottom: idx === sessions.length - 1 ? 'none' : '1px solid rgba(255, 255, 255, 0.04)',
                    fontSize: '11px',
                    fontFamily: 'monospace',
                    alignItems: 'center',
                  }}
                >
                  <div style={{ fontWeight: 600, color: '#60a5fa' }}>{s.sessionId.substring(0, 12)}...</div>
                  <div style={{ opacity: 0.95, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={s.workspaceUrn}>
                    <span style={{ fontWeight: 600, color: '#f1f5f9' }}>
                      {s.workspaceLabel || s.workspaceUrn}
                    </span>
                    {s.workspaceLabel && s.workspaceLabel !== s.workspaceUrn && (
                      <span style={{ marginLeft: '6px', fontSize: '10px', color: '#94a3b8' }}>
                        ({s.workspaceUrn.replace(/^urn:dsh:workspace:/, '')})
                      </span>
                    )}
                  </div>
                  <div>
                    <span
                      style={{
                        padding: '2px 6px',
                        borderRadius: '4px',
                        backgroundColor: s.isLeaseActive ? 'rgba(16, 185, 129, 0.15)' : 'rgba(255, 255, 255, 0.08)',
                        color: s.isLeaseActive ? '#34d399' : '#9ca3af',
                        fontSize: '10px',
                      }}
                    >
                      {s.leaseHolder}
                    </span>
                  </div>
                  <div style={{ textAlign: 'right' }}>
                    {s.leaseHolder !== localNodeId && (
                      <button
                        type="button"
                        onClick={() => handleClaimSession(s.sessionId, s.leaseHolder)}
                        style={{
                          padding: '3px 8px',
                          borderRadius: '4px',
                          backgroundColor: '#2563eb',
                          border: 'none',
                          color: '#fff',
                          fontSize: '10px',
                          cursor: 'pointer'
                        }}
                      >
                        {t('settings.cluster.claim')}
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )
      )}
    </div>
  );
}
