import React, { useState, useEffect } from 'react';
import type { KnowledgeSettingsKey } from './locales.js';

interface FactItem {
  id: string;
  subject: string;
  predicate: string;
  object: string;
  confidence: number;
  securityLabel: string;
  status: string;
  scopeType: 'public' | 'group' | 'user' | 'repo';
  scopeId: string;
  author: string;
}

export interface KnowledgeSectionProps {
  close?: () => void;
  t?: (key: KnowledgeSettingsKey) => string;
}

export function KnowledgeSettingsSection({ t = (k: string) => k }: KnowledgeSectionProps) {
  const [facts, setFacts] = useState<FactItem[]>([]);
  const [filter, setFilter] = useState('');
  const [scopeFilter, setScopeFilter] = useState<'all' | 'user' | 'group' | 'repo' | 'public'>('all');
  const [loading, setLoading] = useState(true);

  // Add memory modal/form state
  const [showAddForm, setShowAddForm] = useState(false);
  const [newSubject, setNewSubject] = useState('');
  const [newPredicate, setNewPredicate] = useState('');
  const [newObject, setNewObject] = useState('');
  const [newScopeType, setNewScopeType] = useState<'user' | 'group' | 'repo' | 'public'>('user');
  const [newScopeTarget, setNewScopeTarget] = useState('');
  const [newTtlSeconds, setNewTtlSeconds] = useState('');
  const [adding, setAdding] = useState(false);
  const [addError, setAddError] = useState<string | null>(null);

  const fetchFacts = async () => {
    setLoading(true);
    try {
      const url = new URL('/api/memory/facts', window.location.origin);
      if (scopeFilter !== 'all') {
        url.searchParams.set('scopeType', scopeFilter);
      }
      if (filter.trim()) {
        url.searchParams.set('search', filter.trim());
      }
      const res = await fetch(url.toString());
      if (res.ok) {
        const data = await res.json();
        setFacts(data.facts || []);
      }
    } catch {
      // Offline / network failure
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchFacts();
  }, [scopeFilter]);

  const handleAddFact = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newSubject.trim() || !newPredicate.trim() || !newObject.trim()) return;

    setAdding(true);
    setAddError(null);

    try {
      const payload: any = {
        subject: newSubject.trim(),
        predicate: newPredicate.trim(),
        object: newObject.trim(),
        scopeType: newScopeType,
        ttlSeconds: newTtlSeconds ? parseInt(newTtlSeconds, 10) : undefined,
      };

      if (newScopeType === 'group' || newScopeType === 'repo') {
        payload.scopeId = newScopeTarget.trim();
      }

      const res = await fetch('/api/memory/facts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });

      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to save memory fact');
      }

      setNewSubject('');
      setNewPredicate('');
      setNewObject('');
      setNewScopeTarget('');
      setNewTtlSeconds('');
      setShowAddForm(false);
      fetchFacts();
    } catch (err: any) {
      setAddError(err.message);
    } finally {
      setAdding(false);
    }
  };

  const handleDeleteFact = async (id: string) => {
    if (!window.confirm(t('settings.knowledge.confirmDelete'))) return;

    try {
      const res = await fetch(`/api/memory/facts?id=${encodeURIComponent(id)}`, {
        method: 'DELETE',
      });
      if (res.ok) {
        fetchFacts();
      } else {
        const err = await res.json();
        alert(err.error || 'Failed to delete memory fact');
      }
    } catch {
      // Ignore network failure
    }
  };

  const filteredFacts = facts.filter(f =>
    f.subject.toLowerCase().includes(filter.toLowerCase()) ||
    f.predicate.toLowerCase().includes(filter.toLowerCase()) ||
    f.object.toLowerCase().includes(filter.toLowerCase()) ||
    (f.scopeId && f.scopeId.toLowerCase().includes(filter.toLowerCase()))
  );

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', maxWidth: '820px' }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: '12px' }}>
        <div>
          <h3 style={{ margin: '0 0 4px 0', fontSize: '15px', fontWeight: 600, color: 'var(--dsw-alias-label-primary, #fff)' }}>
            {t('settings.knowledge.title')}
          </h3>
          <p style={{ margin: 0, fontSize: '12px', color: 'var(--dsw-alias-label-tertiary, #9ca3af)' }}>
            {t('settings.knowledge.description')}
          </p>
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
            {t('settings.knowledge.addFact')}
          </button>
          <button
            type="button"
            onClick={fetchFacts}
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
            {t('settings.knowledge.refresh')}
          </button>
        </div>
      </div>

      {/* Add Memory Form Modal */}
      {showAddForm && (
        <form
          onSubmit={handleAddFact}
          style={{
            display: 'flex',
            flexDirection: 'column',
            gap: '12px',
            padding: '16px',
            borderRadius: '8px',
            backgroundColor: 'rgba(255, 255, 255, 0.03)',
            border: '1px solid rgba(255, 255, 255, 0.1)',
          }}
        >
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '10px' }}>
            <input
              type="text"
              required
              value={newSubject}
              onChange={e => setNewSubject(e.target.value)}
              placeholder={t('settings.knowledge.subjectPlaceholder')}
              style={{
                padding: '8px 12px',
                borderRadius: '6px',
                backgroundColor: 'rgba(0, 0, 0, 0.25)',
                border: '1px solid rgba(255, 255, 255, 0.12)',
                color: 'var(--dsw-alias-label-primary, #fff)',
                fontSize: '12px',
                outline: 'none',
              }}
            />
            <input
              type="text"
              required
              value={newPredicate}
              onChange={e => setNewPredicate(e.target.value)}
              placeholder={t('settings.knowledge.predicatePlaceholder')}
              style={{
                padding: '8px 12px',
                borderRadius: '6px',
                backgroundColor: 'rgba(0, 0, 0, 0.25)',
                border: '1px solid rgba(255, 255, 255, 0.12)',
                color: 'var(--dsw-alias-label-primary, #fff)',
                fontSize: '12px',
                outline: 'none',
              }}
            />
            <input
              type="text"
              required
              value={newObject}
              onChange={e => setNewObject(e.target.value)}
              placeholder={t('settings.knowledge.objectPlaceholder')}
              style={{
                padding: '8px 12px',
                borderRadius: '6px',
                backgroundColor: 'rgba(0, 0, 0, 0.25)',
                border: '1px solid rgba(255, 255, 255, 0.12)',
                color: 'var(--dsw-alias-label-primary, #fff)',
                fontSize: '12px',
                outline: 'none',
              }}
            />
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.5fr 1fr', gap: '10px', alignItems: 'center' }}>
            <select
              value={newScopeType}
              onChange={e => setNewScopeType(e.target.value as any)}
              style={{
                padding: '8px 12px',
                borderRadius: '6px',
                backgroundColor: 'rgba(0, 0, 0, 0.25)',
                border: '1px solid rgba(255, 255, 255, 0.12)',
                color: 'var(--dsw-alias-label-primary, #fff)',
                fontSize: '12px',
                outline: 'none',
              }}
            >
              <option value="user">{t('settings.knowledge.scopePersonal')}</option>
              <option value="group">{t('settings.knowledge.scopeGroup')}</option>
              <option value="repo">{t('settings.knowledge.scopeRepo')}</option>
              <option value="public">{t('settings.knowledge.scopePublic')}</option>
            </select>

            {(newScopeType === 'group' || newScopeType === 'repo') && (
              <input
                type="text"
                required
                value={newScopeTarget}
                onChange={e => setNewScopeTarget(e.target.value)}
                placeholder={newScopeType === 'group' ? t('settings.knowledge.groupIdPlaceholder') : t('settings.knowledge.repoIdPlaceholder')}
                style={{
                  padding: '8px 12px',
                  borderRadius: '6px',
                  backgroundColor: 'rgba(0, 0, 0, 0.25)',
                  border: '1px solid rgba(255, 255, 255, 0.12)',
                  color: 'var(--dsw-alias-label-primary, #fff)',
                  fontSize: '12px',
                  outline: 'none',
                }}
              />
            )}

            <input
              type="number"
              value={newTtlSeconds}
              onChange={e => setNewTtlSeconds(e.target.value)}
              placeholder={t('settings.knowledge.ttlPlaceholder')}
              style={{
                padding: '8px 12px',
                borderRadius: '6px',
                backgroundColor: 'rgba(0, 0, 0, 0.25)',
                border: '1px solid rgba(255, 255, 255, 0.12)',
                color: 'var(--dsw-alias-label-primary, #fff)',
                fontSize: '12px',
                outline: 'none',
              }}
            />
          </div>

          {addError && (
            <div style={{ fontSize: '11px', color: '#f87171' }}>
              {addError}
            </div>
          )}

          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '8px', marginTop: '4px' }}>
            <button
              type="button"
              onClick={() => setShowAddForm(false)}
              style={{
                padding: '5px 12px',
                borderRadius: '6px',
                backgroundColor: 'transparent',
                border: '1px solid rgba(255, 255, 255, 0.12)',
                color: 'var(--dsw-alias-label-secondary, #d1d5db)',
                fontSize: '12px',
                cursor: 'pointer',
              }}
            >
              {t('settings.knowledge.cancel')}
            </button>
            <button
              type="submit"
              disabled={adding}
              style={{
                padding: '5px 14px',
                borderRadius: '6px',
                backgroundColor: '#3b82f6',
                border: 'none',
                color: '#fff',
                fontSize: '12px',
                fontWeight: 500,
                cursor: adding ? 'not-allowed' : 'pointer',
                opacity: adding ? 0.6 : 1,
              }}
            >
              {adding ? t('settings.knowledge.loading') : t('settings.knowledge.save')}
            </button>
          </div>
        </form>
      )}

      {/* Scope Filtering Tabs & Search Bar */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '12px' }}>
        <div style={{ display: 'flex', gap: '6px' }}>
          {(['all', 'user', 'group', 'repo', 'public'] as const).map(sc => {
            const labelMap = {
              all: t('settings.knowledge.scopeAll'),
              user: t('settings.knowledge.scopePersonal'),
              group: t('settings.knowledge.scopeGroup'),
              repo: t('settings.knowledge.scopeRepo'),
              public: t('settings.knowledge.scopePublic'),
            };
            const active = scopeFilter === sc;
            return (
              <button
                key={sc}
                type="button"
                onClick={() => setScopeFilter(sc)}
                style={{
                  padding: '4px 10px',
                  borderRadius: '14px',
                  fontSize: '11px',
                  fontWeight: active ? 600 : 400,
                  backgroundColor: active ? 'rgba(59, 130, 246, 0.2)' : 'rgba(255, 255, 255, 0.05)',
                  border: active ? '1px solid rgba(59, 130, 246, 0.4)' : '1px solid rgba(255, 255, 255, 0.08)',
                  color: active ? '#60a5fa' : 'var(--dsw-alias-label-secondary, #d1d5db)',
                  cursor: 'pointer',
                }}
              >
                {labelMap[sc]}
              </button>
            );
          })}
        </div>

        <input
          type="text"
          value={filter}
          onChange={e => setFilter(e.target.value)}
          placeholder={t('settings.knowledge.searchPlaceholder')}
          style={{
            width: '280px',
            padding: '6px 12px',
            borderRadius: '6px',
            backgroundColor: 'rgba(0, 0, 0, 0.2)',
            border: '1px solid rgba(255, 255, 255, 0.1)',
            color: 'var(--dsw-alias-label-primary, #fff)',
            fontSize: '12px',
            outline: 'none',
          }}
        />
      </div>

      {loading ? (
        <div style={{ fontSize: '12px', color: 'var(--dsw-alias-label-tertiary, #9ca3af)', padding: '20px 0' }}>
          {t('settings.knowledge.loading')}
        </div>
      ) : filteredFacts.length === 0 ? (
        <div style={{ fontSize: '12px', color: 'var(--dsw-alias-label-tertiary, #9ca3af)', padding: '20px 0' }}>
          {t('settings.knowledge.empty')}
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
              gridTemplateColumns: '2.5fr 2fr 2.5fr 1.2fr 48px',
              padding: '8px 12px',
              backgroundColor: 'rgba(255, 255, 255, 0.04)',
              borderBottom: '1px solid rgba(255, 255, 255, 0.06)',
              fontSize: '11px',
              fontWeight: 600,
              color: 'var(--dsw-alias-label-secondary, #d1d5db)',
            }}
          >
            <div>{t('settings.knowledge.colSubject')}</div>
            <div>{t('settings.knowledge.colPredicate')}</div>
            <div>{t('settings.knowledge.colObject')}</div>
            <div>{t('settings.knowledge.colScope')}</div>
            <div style={{ textAlign: 'right' }}>{t('settings.knowledge.colActions')}</div>
          </div>

          <div style={{ maxHeight: '460px', overflowY: 'auto' }}>
            {filteredFacts.map((fact, idx) => {
              const scopeBg =
                fact.scopeType === 'user' ? 'rgba(59, 130, 246, 0.12)' :
                fact.scopeType === 'group' ? 'rgba(168, 85, 247, 0.12)' :
                fact.scopeType === 'repo' ? 'rgba(234, 179, 8, 0.12)' :
                'rgba(16, 185, 129, 0.12)';
              const scopeColor =
                fact.scopeType === 'user' ? '#60a5fa' :
                fact.scopeType === 'group' ? '#c084fc' :
                fact.scopeType === 'repo' ? '#facc15' :
                '#34d399';

              return (
                <div
                  key={fact.id || idx}
                  style={{
                    display: 'grid',
                    gridTemplateColumns: '2.5fr 2fr 2.5fr 1.2fr 48px',
                    padding: '9px 12px',
                    borderBottom: idx === filteredFacts.length - 1 ? 'none' : '1px solid rgba(255, 255, 255, 0.04)',
                    fontSize: '11px',
                    fontFamily: 'monospace',
                    alignItems: 'center',
                  }}
                >
                  <div style={{ wordBreak: 'break-all', color: '#60a5fa' }}>{fact.subject}</div>
                  <div style={{ wordBreak: 'break-all', opacity: 0.85 }}>{fact.predicate}</div>
                  <div style={{ wordBreak: 'break-all', color: '#34d399' }}>{fact.object}</div>
                  <div>
                    <span
                      style={{
                        padding: '2px 6px',
                        borderRadius: '4px',
                        backgroundColor: scopeBg,
                        color: scopeColor,
                        fontSize: '10px',
                        display: 'inline-block',
                      }}
                      title={fact.scopeId}
                    >
                      {fact.scopeId}
                    </span>
                  </div>
                  <div style={{ textAlign: 'right' }}>
                    <button
                      type="button"
                      onClick={() => handleDeleteFact(fact.id)}
                      title={t('settings.knowledge.delete')}
                      style={{
                        padding: '2px 6px',
                        borderRadius: '4px',
                        backgroundColor: 'transparent',
                        border: 'none',
                        color: 'rgba(239, 68, 68, 0.8)',
                        cursor: 'pointer',
                        fontSize: '12px',
                      }}
                    >
                      ×
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
