import React, { useState, useEffect, useRef } from 'react';
import {
  IconChevronDownOutline14,
  IconCheckOutline14,
  IconUserOutline16,
  useAnchoredPosition,
  useDismissOnOutsidePointer,
} from '@deepseek-ai/dsh-client-ui-primitives';
import { createPortal } from 'react-dom';
import { parseTenantIdentity, fetchTenantIdentity } from './identity.js';
import type { AuthSettingsKey } from './locales.js';

export interface GroupWorkspaceSwitcherProps {
  t?: (key: AuthSettingsKey) => string;
}

const SCOPE_STORAGE_KEY = 'dsh-active-scope';

export function GroupWorkspaceSwitcher({ t = (k: string) => k }: GroupWorkspaceSwitcherProps) {
  const [identity, setIdentity] = useState(() => parseTenantIdentity());
  const [activeScope, setActiveScope] = useState<string>(() => {
    if (typeof window !== 'undefined') {
      return localStorage.getItem(SCOPE_STORAGE_KEY) || 'personal';
    }
    return 'personal';
  });

  const [open, setOpen] = useState(false);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const rootRef = useRef<HTMLDivElement>(null);

  useDismissOnOutsidePointer(rootRef, open, setOpen, menuRef);

  const menuPosition = useAnchoredPosition({
    open,
    anchorRef: triggerRef,
    panelRef: menuRef,
    side: 'bottom',
    gap: 6,
    margin: 12,
  });

  useEffect(() => {
    let live = true;
    // The session cookie is HttpOnly, so identity must come from the server.
    fetchTenantIdentity().then((id) => { if (live) setIdentity(id); });
    return () => { live = false; };
  }, []);

  const selectScope = (scope: string) => {
    setActiveScope(scope);
    if (typeof window !== 'undefined') {
      localStorage.setItem(SCOPE_STORAGE_KEY, scope);
      window.dispatchEvent(new CustomEvent('dsh:scope-change', { detail: { scope } }));
    }
    setOpen(false);
  };

  const isPersonal = activeScope === 'personal';
  const displayLabel = isPersonal
    ? `${t('group.switcher.personal')}: ${identity.username}`
    : `${t('group.switcher.group')}: ${activeScope}`;

  return (
    <div ref={rootRef} style={{ display: 'inline-flex', alignItems: 'center', position: 'relative' }}>
      <button
        ref={triggerRef}
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          setOpen((prev) => !prev);
        }}
        aria-expanded={open}
        aria-haspopup="menu"
        style={{
          display: 'inline-flex',
          alignItems: 'center',
          gap: '6px',
          background: open ? 'rgba(255, 255, 255, 0.08)' : 'transparent',
          border: '1px solid',
          borderColor: open ? 'rgba(255, 255, 255, 0.15)' : 'rgba(255, 255, 255, 0.06)',
          borderRadius: '6px',
          padding: '3px 8px',
          cursor: 'pointer',
          color: 'var(--dsw-alias-label-primary, #ffffff)',
          fontSize: '12px',
          fontWeight: 600,
          lineHeight: '18px',
          transition: 'all 150ms ease',
          outline: 'none',
        }}
        onMouseEnter={(e) => {
          e.currentTarget.style.borderColor = 'rgba(255, 255, 255, 0.2)';
          e.currentTarget.style.background = 'rgba(255, 255, 255, 0.05)';
        }}
        onMouseLeave={(e) => {
          e.currentTarget.style.borderColor = open ? 'rgba(255, 255, 255, 0.15)' : 'rgba(255, 255, 255, 0.06)';
          e.currentTarget.style.background = open ? 'rgba(255, 255, 255, 0.08)' : 'transparent';
        }}
      >
        <span
          style={{
            maxWidth: '140px',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
            letterSpacing: '-0.01em',
          }}
        >
          {displayLabel}
        </span>
        <span
          style={{
            display: 'inline-flex',
            transform: open ? 'rotate(180deg)' : 'none',
            transition: 'transform 150ms ease',
            color: 'var(--dsw-alias-label-tertiary, #9ca3af)',
          }}
        >
          <IconChevronDownOutline14 size={12} />
        </span>
      </button>

      {open &&
        createPortal(
          <div
            ref={menuRef}
            role="menu"
            style={{
              position: 'fixed',
              zIndex: 9999,
              minWidth: '220px',
              padding: '6px',
              borderRadius: '8px',
              backgroundColor: '#18191b',
              border: '1px solid rgba(255, 255, 255, 0.12)',
              boxShadow: '0 8px 24px rgba(0, 0, 0, 0.45)',
              backdropFilter: 'blur(16px)',
              display: 'flex',
              flexDirection: 'column',
              gap: '4px',
              ...menuPosition,
            }}
          >
            <div
              style={{
                padding: '6px 8px 4px 8px',
                fontSize: '11px',
                fontWeight: 600,
                textTransform: 'uppercase',
                letterSpacing: '0.05em',
                color: 'var(--dsw-alias-label-tertiary, #9ca3af)',
              }}
            >
              {t('group.switcher.switchScope')}
            </div>

            {/* Personal Scope Option */}
            <div
              role="menuitem"
              onClick={() => selectScope('personal')}
              style={{
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                padding: '8px 10px',
                borderRadius: '6px',
                cursor: 'pointer',
                backgroundColor: isPersonal ? 'rgba(59, 130, 246, 0.12)' : 'transparent',
                color: isPersonal ? '#60a5fa' : 'var(--dsw-alias-label-primary, #ffffff)',
                transition: 'background 100ms ease',
              }}
              onMouseEnter={(e) => {
                if (!isPersonal) e.currentTarget.style.backgroundColor = 'rgba(255, 255, 255, 0.05)';
              }}
              onMouseLeave={(e) => {
                if (!isPersonal) e.currentTarget.style.backgroundColor = 'transparent';
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <IconUserOutline16 size={14} />
                <div>
                  <div style={{ fontSize: '12px', fontWeight: 600 }}>{t('group.switcher.personal')}</div>
                  <div style={{ fontSize: '10px', opacity: 0.6, fontFamily: 'monospace' }}>
                    @{identity.username}
                  </div>
                </div>
              </div>
              {isPersonal && <IconCheckOutline14 size={14} />}
            </div>

            {/* Separator if user has groups */}
            {identity.groups.length > 0 && (
              <div style={{ height: '1px', backgroundColor: 'rgba(255, 255, 255, 0.06)', margin: '4px 0' }} />
            )}

            {/* Group Scope Options */}
            {identity.groups.map((group) => {
              const isCurrent = activeScope === group;
              return (
                <div
                  key={group}
                  role="menuitem"
                  onClick={() => selectScope(group)}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    padding: '8px 10px',
                    borderRadius: '6px',
                    cursor: 'pointer',
                    backgroundColor: isCurrent ? 'rgba(16, 185, 129, 0.12)' : 'transparent',
                    color: isCurrent ? '#34d399' : 'var(--dsw-alias-label-primary, #ffffff)',
                    transition: 'background 100ms ease',
                  }}
                  onMouseEnter={(e) => {
                    if (!isCurrent) e.currentTarget.style.backgroundColor = 'rgba(255, 255, 255, 0.05)';
                  }}
                  onMouseLeave={(e) => {
                    if (!isCurrent) e.currentTarget.style.backgroundColor = 'transparent';
                  }}
                >
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <span
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        width: '18px',
                        height: '18px',
                        borderRadius: '4px',
                        backgroundColor: isCurrent ? 'rgba(16, 185, 129, 0.2)' : 'rgba(255, 255, 255, 0.08)',
                        fontSize: '10px',
                        fontWeight: 700,
                        fontFamily: 'monospace',
                        textTransform: 'uppercase',
                      }}
                    >
                      {group.slice(0, 2)}
                    </span>
                    <div>
                      <div style={{ fontSize: '12px', fontWeight: 600 }}>{group}</div>
                      <div style={{ fontSize: '10px', opacity: 0.6 }}>{t('group.switcher.group')}</div>
                    </div>
                  </div>
                  {isCurrent && <IconCheckOutline14 size={14} />}
                </div>
              );
            })}
          </div>,
          document.body
        )}
    </div>
  );
}
