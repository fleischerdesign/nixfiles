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
  epistemicClass?: 'axiom' | 'evidence' | 'hypothesis';
}

export interface KnowledgeSectionProps {
  close?: () => void;
  t?: (key: KnowledgeSettingsKey) => string;
}

export function KnowledgeSettingsSection({ t = (k: string) => k }: KnowledgeSectionProps) {
  const [facts, setFacts] = useState<FactItem[]>([]);
  const [filter, setFilter] = useState('');
  const [scopeFilter, setScopeFilter] = useState<'all' | 'user' | 'group' | 'repo' | 'public'>('all');
  const [classFilter, setClassFilter] = useState<'all' | 'axiom' | 'evidence' | 'hypothesis'>('all');
  const [loading, setLoading] = useState(true);

  // Add memory modal/form state
  const [showAddForm, setShowAddForm] = useState(false);
  const [newSubject, setNewSubject] = useState('');
  const [newPredicate, setNewPredicate] = useState('');
  const [newObject, setNewObject] = useState('');
  const [newScopeType, setNewScopeType] = useState<'user' | 'group' | 'repo' | 'public'>('user');
  const [newScopeTarget, setNewScopeTarget] = useState('');
  const [newTtlSeconds, setNewTtlSeconds] = useState('');
  const [newClass, setNewClass] = useState<'evidence' | 'hypothesis'>('evidence');
  const [adding, setAdding] = useState(false);
  const [addError, setAddError] = useState<string | null>(null);

  const fetchFacts = async () => {
    setLoading(true);
    try {
      const url = new URL('/api/memory/facts', window.location.origin);
      if (scopeFilter !== 'all') {
        url.searchParams.set('scopeType', scopeFilter);
      }
      if (classFilter !== 'all') {
        url.searchParams.set('epistemicClass', classFilter);
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
  }, [scopeFilter, classFilter]);

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
        epistemicClass: newClass,
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

  const handleDeleteFact = async (fact: FactItem) => {
    if (fact.epistemicClass === 'axiom') {
      alert('Axioms are immutable and cannot be deleted.');
      return;
    }

    if (!window.confirm(t('settings.knowledge.confirmDelete'))) return;

    try {
      const res = await fetch(`/api/memory/facts?id=${encodeURIComponent(fact.id)}`, {
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
    f.object.toLowerCase().includes(filter.toLowerCase())
  );

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', padding: '4px 0' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <div>
          <h3 style={{ margin: 0, fontSize: '15px', fontWeight: 600, color: 'var(--dsw-alias-label-primary, #fff)' }}>
            {t('settings.knowledge.title')}
          </h3>
          <p style={{ margin: '4px 0 0', fontSize: '12px', color: 'var(--dsw-alias-label-secondary, #9ca3af)' }}>
            {t('settings.knowledge.description')}
          </p>
        </div>
        <div style={{ display: 'flex', gap: '8px' }}>
          <button
            type="button"
            onClick={fetchFacts}
            disabled={loading}
            style={{
              padding: '6px 12px',
              borderRadius: '6px',
              fontSize: '12px',
              cursor: 'pointer',
              backgroundColor: 'rgba(255, 255, 255, 0.05)',
              border: '1px solid rgba(255, 255, 255, 0.1)',
              color: 'var(--dsw-alias-label-primary, #fff)',
            }}
          >
            {t('settings.knowledge.refresh')}
          </button>
          <button
            type="button"
            onClick={() => setShowAddForm(!showAddForm)}
            style={{
              padding: '6px 14px',
              borderRadius: '6px',
              fontSize: '12px',
              fontWeight: 500,
              cursor: 'pointer',
              backgroundColor: '#3b82f6',
              border: 'none',
              color: '#fff',
            }}
          >
            {showAddForm ? t('settings.knowledge.cancel') : t('settings.knowledge.addFact')}
          </button>
        </div>
      </div>

      {showAddForm && (
        <form
          onSubmit={handleAddFact}
          style={{
            padding: '16px',
            borderRadius: '8px',
            backgroundColor: 'rgba(255, 255, 255, 0.03)',
            border: '1px solid rgba(255, 255, 255, 0.1)',
            display: 'flex',
            flexDirection: 'column',
            gap: '12px',
          }}
        >
          {addError && (
            <div style={{ padding: '8px 12px', borderRadius: '4px', backgroundColor: 'rgba(239, 68, 68, 0.15)', color: '#ef4444', fontSize: '12px' }}>
              {addError}
            </div>
          )}

          <div style={{ display: 'grid', gridTemplateColumns: '1.2fr 1fr 1.2fr', gap: '8px' }}>
            <input
              type="text"
              placeholder={t('settings.knowledge.subjectPlaceholder')}
              value={newSubject}
              onChange={e => setNewSubject(e.target.value)}
              required
              style={{
                padding: '6px 10px',
                borderRadius: '6px',
                backgroundColor: 'rgba(0, 0, 0, 0.2)',
                border: '1px solid rgba(255, 255, 255, 0.1)',
                color: 'var(--dsw-alias-label-primary, #fff)',
                fontSize: '12px',
              }}
            />
            <input
              type="text"
              placeholder={t('settings.knowledge.predicatePlaceholder')}
              value={newPredicate}
              onChange={e => setNewPredicate(e.target.value)}
              required
              style={{
                padding: '6px 10px',
                borderRadius: '6px',
                backgroundColor: 'rgba(0, 0, 0, 0.2)',
                border: '1px solid rgba(255, 255, 255, 0.1)',
                color: 'var(--dsw-alias-label-primary, #fff)',
                fontSize: '12px',
              }}
            />
            <input
              type="text"
              placeholder={t('settings.knowledge.objectPlaceholder')}
              value={newObject}
              onChange={e => setNewObject(e.target.value)}
              required
              style={{
                padding: '6px 10px',
                borderRadius: '6px',
                backgroundColor: 'rgba(0, 0, 0, 0.2)',
                border: '1px solid rgba(255, 255, 255, 0.1)',
                color: 'var(--dsw-alias-label-primary, #fff)',
                fontSize: '12px',
              }}
            />
          </div>

          <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
            <select
              value={newClass}
              onChange={e => setNewClass(e.target.value as any)}
              style={{
                padding: '6px 10px',
                borderRadius: '6px',
                backgroundColor: 'rgba(0, 0, 0, 0.2)',
                border: '1px solid rgba(255, 255, 255, 0.1)',
                color: 'var(--dsw-alias-label-primary, #fff)',
                fontSize: '12px',
              }}
            >
              <option value="evidence">Evidence (Verified)</option>
              <option value="hypothesis">Hypothesis (Tentative)</option>
            </select>

            <select
              value={newScopeType}
              onChange={e => setNewScopeType(e.target.value as any)}
              style={{
                padding: '6px 10px',
                borderRadius: '6px',
                backgroundColor: 'rgba(0, 0, 0, 0.2)',
                border: '1px solid rgba(255, 255, 255, 0.1)',
                color: 'var(--dsw-alias-label-primary, #fff)',
                fontSize: '12px',
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
                placeholder={newScopeType === 'group' ? t('settings.knowledge.groupIdPlaceholder') : t('settings.knowledge.repoIdPlaceholder')}
                value={newScopeTarget}
                onChange={e => setNewScopeTarget(e.target.value)}
                required
                style={{
                  padding: '6px 10px',
                  borderRadius: '6px',
                  backgroundColor: 'rgba(0, 0, 0, 0.2)',
                  border: '1px solid rgba(255, 255, 255, 0.1)',
                  color: 'var(--dsw-alias-label-primary, #fff)',
                  fontSize: '12px',
                  width: '180px',
                }}
              />
            )}

            <button
              type="submit"
              disabled={adding}
              style={{
                marginLeft: 'auto',
                padding: '6px 16px',
                borderRadius: '6px',
                fontSize: '12px',
                fontWeight: 500,
                cursor: 'pointer',
                backgroundColor: '#10b981',
                border: 'none',
                color: '#fff',
              }}
            >
              {adding ? '...' : t('settings.knowledge.save')}
            </button>
          </div>
        </form>
      )}

      {/* Filter and Search Bar */}
      <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
        <div style={{ display: 'flex', borderRadius: '6px', overflow: 'hidden', border: '1px solid rgba(255, 255, 255, 0.1)' }}>
          {(['all', 'user', 'group', 'repo', 'public'] as const).map(sc => (
            <button
              key={sc}
              type="button"
              onClick={() => setScopeFilter(sc)}
              style={{
                padding: '4px 10px',
                fontSize: '11px',
                border: 'none',
                cursor: 'pointer',
                backgroundColor: scopeFilter === sc ? 'rgba(59, 130, 246, 0.2)' : 'rgba(0, 0, 0, 0.1)',
                color: scopeFilter === sc ? '#60a5fa' : 'var(--dsw-alias-label-secondary, #9ca3af)',
              }}
            >
              {sc === 'all' ? t('settings.knowledge.scopeAll') :
               sc === 'user' ? t('settings.knowledge.scopePersonal') :
               sc === 'group' ? t('settings.knowledge.scopeGroup') :
               sc === 'repo' ? t('settings.knowledge.scopeRepo') :
               t('settings.knowledge.scopePublic')}
            </button>
          ))}
        </div>

        <div style={{ display: 'flex', borderRadius: '6px', overflow: 'hidden', border: '1px solid rgba(255, 255, 255, 0.1)' }}>
          {(['all', 'axiom', 'evidence', 'hypothesis'] as const).map(ec => (
            <button
              key={ec}
              type="button"
              onClick={() => setClassFilter(ec)}
              style={{
                padding: '4px 8px',
                fontSize: '11px',
                border: 'none',
                cursor: 'pointer',
                backgroundColor: classFilter === ec ? 'rgba(16, 185, 129, 0.2)' : 'rgba(0, 0, 0, 0.1)',
                color: classFilter === ec ? '#34d399' : 'var(--dsw-alias-label-secondary, #9ca3af)',
              }}
            >
              {ec === 'all' ? 'All Classes' : ec === 'axiom' ? '🛡️ Axiom' : ec === 'evidence' ? '✓ Evidence' : '📝 Hypothesis'}
            </button>
          ))}
        </div>

        <input
          type="text"
          value={filter}
          onChange={e => setFilter(e.target.value)}
          placeholder={t('settings.knowledge.searchPlaceholder')}
          style={{
            marginLeft: 'auto',
            width: '260px',
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
              gridTemplateColumns: '80px 2.2fr 1.8fr 2.2fr 1.1fr 40px',
              padding: '8px 12px',
              backgroundColor: 'rgba(255, 255, 255, 0.04)',
              borderBottom: '1px solid rgba(255, 255, 255, 0.06)',
              fontSize: '11px',
              fontWeight: 600,
              color: 'var(--dsw-alias-label-secondary, #d1d5db)',
            }}
          >
            <div>{t('settings.knowledge.colClass')}</div>
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

              const isAxiom = fact.epistemicClass === 'axiom';
              const classLabel = isAxiom ? '🛡️ Axiom' : fact.epistemicClass === 'hypothesis' ? '📝 Hypo' : '✓ Evid';
              const classColor = isAxiom ? '#60a5fa' : fact.epistemicClass === 'hypothesis' ? '#facc15' : '#34d399';

              return (
                <div
                  key={fact.id || idx}
                  style={{
                    display: 'grid',
                    gridTemplateColumns: '80px 2.2fr 1.8fr 2.2fr 1.1fr 40px',
                    padding: '9px 12px',
                    borderBottom: idx === filteredFacts.length - 1 ? 'none' : '1px solid rgba(255, 255, 255, 0.04)',
                    fontSize: '11px',
                    fontFamily: 'monospace',
                    alignItems: 'center',
                  }}
                >
                  <div style={{ fontSize: '10px', color: classColor, fontWeight: 500 }}>
                    {classLabel}
                  </div>
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
                    {!isAxiom ? (
                      <button
                        type="button"
                        onClick={() => handleDeleteFact(fact)}
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
                    ) : (
                      <span style={{ fontSize: '10px', opacity: 0.4 }} title="Axiom: Immutable">🔒</span>
                    )}
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
