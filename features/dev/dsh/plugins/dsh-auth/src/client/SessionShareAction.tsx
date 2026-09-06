import React, { useState, useEffect, useRef } from 'react';
import {
  IconShareOutline16,
  IconCheckOutline14,
  useAnchoredPosition,
  useDismissOnOutsidePointer,
} from '@deepseek-ai/dsh-client-ui-primitives';
import { createPortal } from 'react-dom';
import { parseTenantIdentity } from './identity.js';
import type { AuthSettingsKey } from './locales.js';

export interface SessionShareActionProps {
  sessionId?: string;
  useSession?: (selector: (snapshot: any) => any) => any;
  t?: (key: AuthSettingsKey) => string;
}

const SESSION_SCOPE_PREFIX = 'dsh-session-scope:';

export function SessionShareAction({ sessionId, useSession, t = (k: string) => k }: SessionShareActionProps) {
  const currentSessionId = sessionId || (useSession ? useSession((s) => s?.id) : undefined);
  const [identity] = useState(() => parseTenantIdentity());

  const [sessionScope, setSessionScope] = useState<string>('personal');
  const [open, setOpen] = useState(false);

  const triggerRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  const rootRef = useRef<HTMLDivElement>(null);

  useDismissOnOutsidePointer(rootRef, open, setOpen, panelRef);

  const panelPosition = useAnchoredPosition({
    open,
    anchorRef: triggerRef,
    panelRef: panelRef,
    side: 'bottom',
    gap: 6,
    margin: 12,
  });

  // Load session scope from storage/state
  useEffect(() => {
    if (currentSessionId && typeof window !== 'undefined') {
      const stored = localStorage.getItem(`${SESSION_SCOPE_PREFIX}${currentSessionId}`);
      if (stored) {
        setSessionScope(stored);
      } else {
        setSessionScope('personal');
      }
    }
  }, [currentSessionId]);

  const updateScope = (scope: string) => {
    setSessionScope(scope);
    if (currentSessionId && typeof window !== 'undefined') {
      localStorage.setItem(`${SESSION_SCOPE_PREFIX}${currentSessionId}`, scope);
      window.dispatchEvent(
        new CustomEvent('dsh:session-scope-change', {
          detail: { sessionId: currentSessionId, scope },
        })
      );
    }
    setOpen(false);
  };

  const isShared = sessionScope !== 'personal';

  return (
    <div ref={rootRef} style={{ display: 'inline-flex', alignItems: 'center', position: 'relative' }}>
      <button
        ref={triggerRef}
        type="button"
        onClick={() => setOpen((prev) => !prev)}
        aria-expanded={open}
        aria-label={t('session.share.action')}
        style={{
          display: 'inline-flex',
          alignItems: 'center',
          gap: '5px',
          height: '24px',
          padding: '0 8px',
          borderRadius: '5px',
          border: '1px solid',
          borderColor: isShared ? 'rgba(52, 211, 153, 0.4)' : 'rgba(255, 255, 255, 0.1)',
          backgroundColor: isShared ? 'rgba(16, 185, 129, 0.12)' : 'transparent',
          color: isShared ? '#34d399' : 'var(--dsw-alias-label-secondary, #d1d5db)',
          fontSize: '11px',
          fontWeight: 600,
          cursor: 'pointer',
          transition: 'all 150ms ease',
          outline: 'none',
        }}
        onMouseEnter={(e) => {
          if (!isShared) {
            e.currentTarget.style.backgroundColor = 'rgba(255, 255, 255, 0.06)';
            e.currentTarget.style.borderColor = 'rgba(255, 255, 255, 0.2)';
          }
        }}
        onMouseLeave={(e) => {
          if (!isShared) {
            e.currentTarget.style.backgroundColor = 'transparent';
            e.currentTarget.style.borderColor = 'rgba(255, 255, 255, 0.1)';
          }
        }}
      >
        <IconShareOutline16 size={13} />
        <span>{isShared ? sessionScope : t('session.share.action')}</span>
      </button>

      {open &&
        createPortal(
          <div
            ref={panelRef}
            style={{
              position: 'fixed',
              zIndex: 9999,
              width: '260px',
              padding: '12px',
              borderRadius: '8px',
              backgroundColor: '#18191b',
              border: '1px solid rgba(255, 255, 255, 0.12)',
              boxShadow: '0 8px 24px rgba(0, 0, 0, 0.5)',
              backdropFilter: 'blur(16px)',
              display: 'flex',
              flexDirection: 'column',
              gap: '10px',
              ...panelPosition,
            }}
          >
            <div>
              <div style={{ fontSize: '12px', fontWeight: 600, color: 'var(--dsw-alias-label-primary, #ffffff)' }}>
                {t('session.share.title')}
              </div>
              <div
                style={{
                  fontSize: '11px',
                  color: 'var(--dsw-alias-label-tertiary, #9ca3af)',
                  lineHeight: '1.4',
                  marginTop: '2px',
                }}
              >
                {t('session.share.description')}
              </div>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
              {/* Private Scope Option */}
              <div
                onClick={() => updateScope('personal')}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  padding: '7px 8px',
                  borderRadius: '6px',
                  cursor: 'pointer',
                  backgroundColor: sessionScope === 'personal' ? 'rgba(59, 130, 246, 0.12)' : 'transparent',
                  color: sessionScope === 'personal' ? '#60a5fa' : 'var(--dsw-alias-label-primary, #ffffff)',
                }}
              >
                <div>
                  <div style={{ fontSize: '11px', fontWeight: 600 }}>{t('session.share.scopePersonal')}</div>
                  <div style={{ fontSize: '10px', opacity: 0.6 }}>@{identity.username}</div>
                </div>
                {sessionScope === 'personal' && <IconCheckOutline14 size={13} />}
              </div>

              {/* Group Scope Options */}
              {identity.groups.map((group) => {
                const isCurrent = sessionScope === group;
                return (
                  <div
                    key={group}
                    onClick={() => updateScope(group)}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      padding: '7px 8px',
                      borderRadius: '6px',
                      cursor: 'pointer',
                      backgroundColor: isCurrent ? 'rgba(16, 185, 129, 0.12)' : 'transparent',
                      color: isCurrent ? '#34d399' : 'var(--dsw-alias-label-primary, #ffffff)',
                    }}
                  >
                    <div>
                      <div style={{ fontSize: '11px', fontWeight: 600 }}>{group}</div>
                      <div style={{ fontSize: '10px', opacity: 0.6 }}>{t('session.share.scopeGroup')}</div>
                    </div>
                    {isCurrent && <IconCheckOutline14 size={13} />}
                  </div>
                );
              })}
            </div>
          </div>,
          document.body
        )}
    </div>
  );
}
