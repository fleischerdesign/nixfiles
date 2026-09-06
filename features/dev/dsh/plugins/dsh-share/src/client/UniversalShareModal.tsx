import React, { useState, useEffect, useRef } from 'react';
import {
  IconCloseOutline16,
  IconCopyOutline16,
  IconCheckOutline14,
  IconTrashOutline16,
} from '@deepseek-ai/dsh-client-ui-primitives';
import { createPortal } from 'react-dom';
import type { ShareLocaleKey } from './locales.js';

export interface UniversalShareModalProps {
  t?: (key: ShareLocaleKey, params?: Record<string, any>) => string;
}

export function UniversalShareModal({ t = (k: string) => k }: UniversalShareModalProps) {
  const [open, setOpen] = useState(false);
  const [targetSessionId, setTargetSessionId] = useState<string | null>(null);
  const [targetSessionTitle, setTargetSessionTitle] = useState<string>('Session');

  const [scope, setScope] = useState<'public' | 'group' | 'restricted'>('public');
  const [permission, setPermission] = useState<'view' | 'fork' | 'collaborate'>('fork');
  const [stripSecrets, setStripSecrets] = useState(true);
  const [copied, setCopied] = useState(false);
  const [activeShares, setActiveShares] = useState<any[]>([]);
  const [latestShareUrl, setLatestShareUrl] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [inviteInput, setInviteInput] = useState('');
  const [acls, setAcls] = useState<any[]>([]);

  const panelRef = useRef<HTMLDivElement>(null);

  // Seamless Menu Injection & Trigger Detection
  useEffect(() => {
    let capturedSessionTitle = 'Session';

    // 1. When user clicks "..." on a session row, capture title from that row
    const handlePointerDown = (e: MouseEvent) => {
      const target = e.target as HTMLElement | null;
      const button = target?.closest('button[aria-label*="Session actions for"], button[aria-label*="会话“"]');
      if (button) {
        const row = button.closest('[role="treeitem"]');
        const titleEl = row?.querySelector('span[class*="title"]');
        if (titleEl) {
          capturedSessionTitle = titleEl.textContent?.trim() || 'Session';
        }
      }
    };

    document.addEventListener('pointerdown', handlePointerDown, true);

    // 2. Safely inject "Share" entry into the portal menu
    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const added of Array.from(mutation.addedNodes)) {
          if (added instanceof HTMLElement) {
            const menu = added.getAttribute('role') === 'menu' ? added : added.querySelector('[role="menu"]');
            if (menu && !menu.querySelector('[data-dsh-share-item]')) {
              const buttons = Array.from(menu.querySelectorAll('button[role="menuitem"]'));
              const isSessionMenu = buttons.some((btn) => {
                const txt = btn.textContent?.toLowerCase() || '';
                return txt.includes('fork') || txt.includes('archive') || txt.includes('归档') || txt.includes('复刻');
              });

              if (isSessionMenu && buttons.length > 0) {
                const sampleBtn = buttons[0];
                const sampleWrap = sampleBtn.parentElement; // .itemWrap
                if (!sampleWrap || !menu.contains(sampleWrap)) continue;

                // Create container element
                const shareWrap = document.createElement('div');
                shareWrap.setAttribute('data-dsh-share-item', 'true');
                shareWrap.className = sampleWrap.className;

                // Create button element
                const shareBtn = document.createElement('button');
                shareBtn.type = 'button';
                shareBtn.role = 'menuitem';
                shareBtn.className = sampleBtn.className;
                shareBtn.style.cursor = 'pointer';

                // Replicate Icon
                const sampleIcon = sampleBtn.querySelector('span[class*="itemIcon"]');
                const iconSpan = document.createElement('span');
                iconSpan.className = sampleIcon ? sampleIcon.className : '';
                iconSpan.innerHTML = `<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M7.95889 1.52285C7.95888 0.826234 8.76055 0.467983 9.27669 0.875208L9.37524 0.967191L15.1317 7.18358C15.5582 7.64419 15.5582 8.35614 15.1317 8.81676L9.37524 15.0331C8.87034 15.578 7.95888 15.2205 7.95889 14.4775V10.8207C7.10614 10.8432 6.31361 10.9316 5.45468 11.2515C4.39484 11.6463 3.18248 12.413 1.64676 13.9425C1.4533 14.135 1.18329 14.1696 0.969086 14.0908C0.74748 14.0091 0.547307 13.7879 0.54859 13.4844L0.55516 13.1315C0.618924 11.3494 1.11153 9.29838 2.27656 7.63787C3.45289 5.96147 5.29554 4.71635 7.95889 4.54797V1.52285ZM9.20911 5.13366C9.20899 5.50567 8.9031 5.77687 8.56523 5.77755C5.99383 5.78282 4.33736 6.8762 3.29964 8.35496C2.54519 9.43014 2.10739 10.7283 1.9152 11.9939C3.04749 11.0323 4.0569 10.4385 5.01917 10.0801C6.29638 9.60449 7.4406 9.56343 8.56429 9.56295C8.9178 9.5628 9.20894 9.84909 9.20911 10.2068L9.20817 13.3737L14.1837 8.00017L9.20817 2.62571L9.20911 5.13366Z" fill="currentColor"/></svg>`;

                // Replicate Label
                const sampleLabel = sampleBtn.querySelector('span[class*="itemLabel"]');
                const labelSpan = document.createElement('span');
                labelSpan.className = sampleLabel ? sampleLabel.className : '';
                labelSpan.textContent = t('share.dialog.title');

                shareBtn.appendChild(iconSpan);
                shareBtn.appendChild(labelSpan);

                // Click event
                shareBtn.addEventListener('click', (ev) => {
                  ev.preventDefault();
                  ev.stopPropagation();
                  // Close menu
                  menu.remove();
                  setTargetSessionId('current');
                  setTargetSessionTitle(capturedSessionTitle);
                  setOpen(true);
                });

                shareWrap.appendChild(shareBtn);

                // Insert cleanly before the last item (Archive) or append
                const lastItemWrap = menu.lastElementChild;
                if (lastItemWrap && lastItemWrap.parentElement === menu) {
                  menu.insertBefore(shareWrap, lastItemWrap);
                } else {
                  menu.appendChild(shareWrap);
                }
              }
            }
          }
        }
      }
    });

    observer.observe(document.body, { childList: true, subtree: true });

    return () => {
      document.removeEventListener('pointerdown', handlePointerDown, true);
      observer.disconnect();
    };
  }, [t]);

  // Load existing shares when modal opens
  useEffect(() => {
    if (open && targetSessionId) {
      fetch(`/api/share/list?sessionId=${encodeURIComponent(targetSessionId)}`)
        .then((res) => (res.ok ? res.json() : { shares: [], acl: [] }))
        .then((data) => {
          setActiveShares(data.shares || []);
          setAcls(data.acl || []);
          if (data.shares && data.shares.length > 0 && !data.shares[0].revoked) {
            setLatestShareUrl(`${window.location.origin}${data.shares[0].shareUrl}`);
          } else {
            setLatestShareUrl(null);
          }
        })
        .catch(() => {});
    }
  }, [open, targetSessionId]);

  const handleCreateShare = async () => {
    if (!targetSessionId) return;
    setLoading(true);
    try {
      const res = await fetch('/api/share/create', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sessionId: targetSessionId,
          title: targetSessionTitle,
          scope: scope === 'group' ? 'group:dev' : scope === 'public' ? 'public' : 'user:local',
          accessMode: 'snapshot',
          permission,
          stripSecrets,
          ttlSeconds: 0,
        }),
      });
      if (res.ok) {
        const data = await res.json();
        const fullUrl = `${window.location.origin}${data.shareUrl}`;
        setLatestShareUrl(fullUrl);
        setActiveShares((prev) => [
          {
            shareId: data.shareId,
            token: data.token,
            shareUrl: data.shareUrl,
            scope: data.scope,
            permission: data.permission,
            createdAt: Date.now(),
            expiresAt: data.expiresAt,
            revoked: false,
          },
          ...prev,
        ]);
      }
    } catch {
      // Handle error
    } finally {
      setLoading(false);
    }
  };

  const handleCopy = () => {
    if (!latestShareUrl) return;
    navigator.clipboard.writeText(latestShareUrl).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2500);
    });
  };

  const handleRevoke = async (shareId: string) => {
    try {
      const res = await fetch('/api/share/revoke', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ shareId }),
      });
      if (res.ok) {
        setActiveShares((prev) =>
          prev.map((s) => (s.shareId === shareId ? { ...s, revoked: true } : s))
        );
        if (activeShares[0]?.shareId === shareId) {
          setLatestShareUrl(null);
        }
      }
    } catch {}
  };

  const handleAddAcl = async () => {
    if (!inviteInput.trim() || !targetSessionId) return;
    const grantee = inviteInput.startsWith('@') ? `user:${inviteInput.slice(1)}` : inviteInput;
    try {
      const res = await fetch('/api/share/acl', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sessionId: targetSessionId,
          grantee,
          permission: 'fork',
        }),
      });
      if (res.ok) {
        setAcls((prev) => [{ grantee, permission: 'fork', grantedAt: Date.now() }, ...prev]);
        setInviteInput('');
      }
    } catch {}
  };

  const handleRevokeAcl = async (grantee: string) => {
    if (!targetSessionId) return;
    try {
      const res = await fetch('/api/share/acl', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sessionId: targetSessionId, grantee, action: 'revoke' }),
      });
      if (res.ok) {
        setAcls((prev) => prev.filter((a) => a.grantee !== grantee));
      }
    } catch {}
  };

  if (!open) return null;

  return createPortal(
    <div
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 10000,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: 'rgba(0, 0, 0, 0.65)',
        backdropFilter: 'blur(8px)',
      }}
      onClick={(e) => {
        if (e.target === e.currentTarget) setOpen(false);
      }}
    >
      <div
        ref={panelRef}
        style={{
          position: 'relative',
          width: '460px',
          maxWidth: '90vw',
          padding: '20px',
          borderRadius: '12px',
          backgroundColor: '#18191b',
          border: '1px solid rgba(255, 255, 255, 0.14)',
          boxShadow: '0 16px 48px rgba(0, 0, 0, 0.7)',
          display: 'flex',
          flexDirection: 'column',
          gap: '16px',
        }}
      >
        {/* Header */}
        <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between' }}>
          <div>
            <div style={{ fontSize: '15px', fontWeight: 600, color: 'var(--dsw-alias-label-primary, #ffffff)' }}>
              {t('share.dialog.title')}: <span style={{ opacity: 0.7 }}>{targetSessionTitle}</span>
            </div>
            <div style={{ fontSize: '12px', color: 'var(--dsw-alias-label-tertiary, #9ca3af)', marginTop: '4px' }}>
              {t('share.dialog.description')}
            </div>
          </div>
          <button
            type="button"
            onClick={() => setOpen(false)}
            style={{
              background: 'none',
              border: 'none',
              color: 'var(--dsw-alias-label-tertiary, #9ca3af)',
              cursor: 'pointer',
              padding: '4px',
            }}
          >
            <IconCloseOutline16 size={18} />
          </button>
        </div>

        {/* People & Group Sharing Section */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
          <div style={{ fontSize: '11px', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.05em', color: '#9ca3af' }}>
            {t('share.dialog.peopleSection')}
          </div>
          <div style={{ display: 'flex', gap: '6px' }}>
            <input
              type="text"
              placeholder={t('share.dialog.invitePlaceholder')}
              value={inviteInput}
              onChange={(e) => setInviteInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') handleAddAcl();
              }}
              style={{
                flex: 1,
                background: 'rgba(255, 255, 255, 0.04)',
                border: '1px solid rgba(255, 255, 255, 0.1)',
                borderRadius: '6px',
                padding: '7px 10px',
                color: '#ffffff',
                fontSize: '12px',
                outline: 'none',
              }}
            />
            <button
              type="button"
              onClick={handleAddAcl}
              style={{
                padding: '7px 14px',
                borderRadius: '6px',
                backgroundColor: 'rgba(255, 255, 255, 0.08)',
                border: '1px solid rgba(255, 255, 255, 0.12)',
                color: '#ffffff',
                fontSize: '12px',
                fontWeight: 600,
                cursor: 'pointer',
              }}
            >
              {t('share.dialog.inviteButton')}
            </button>
          </div>

          {/* ACL List */}
          {acls.length > 0 && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', marginTop: '4px' }}>
              {acls.map((acl) => (
                <div
                  key={acl.grantee}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    padding: '6px 10px',
                    borderRadius: '6px',
                    backgroundColor: 'rgba(255, 255, 255, 0.03)',
                    fontSize: '12px',
                  }}
                >
                  <span style={{ fontFamily: 'monospace', color: '#60a5fa' }}>{acl.grantee}</span>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <span style={{ opacity: 0.7, fontSize: '11px' }}>{acl.permission}</span>
                    <button
                      type="button"
                      onClick={() => handleRevokeAcl(acl.grantee)}
                      style={{ background: 'none', border: 'none', color: '#ef4444', cursor: 'pointer', padding: 0 }}
                    >
                      <IconTrashOutline16 size={13} />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        <div style={{ height: '1px', backgroundColor: 'rgba(255, 255, 255, 0.08)' }} />

        {/* General Link Sharing Section */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
          <div style={{ fontSize: '11px', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.05em', color: '#9ca3af' }}>
            {t('share.dialog.linkSection')}
          </div>

          {/* Scope & Permission Selectors */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px' }}>
            <select
              value={scope}
              onChange={(e) => setScope(e.target.value as any)}
              style={{
                background: 'rgba(255, 255, 255, 0.04)',
                border: '1px solid rgba(255, 255, 255, 0.1)',
                borderRadius: '6px',
                padding: '7px 8px',
                color: '#ffffff',
                fontSize: '12px',
                outline: 'none',
              }}
            >
              <option value="public" style={{ background: '#1e2022' }}>{t('share.dialog.scopePublic')}</option>
              <option value="group" style={{ background: '#1e2022' }}>{t('share.dialog.scopeGroup')}</option>
              <option value="restricted" style={{ background: '#1e2022' }}>{t('share.dialog.scopeRestricted')}</option>
            </select>

            <select
              value={permission}
              onChange={(e) => setPermission(e.target.value as any)}
              style={{
                background: 'rgba(255, 255, 255, 0.04)',
                border: '1px solid rgba(255, 255, 255, 0.1)',
                borderRadius: '6px',
                padding: '7px 8px',
                color: '#ffffff',
                fontSize: '12px',
                outline: 'none',
              }}
            >
              <option value="view" style={{ background: '#1e2022' }}>{t('share.dialog.permView')}</option>
              <option value="fork" style={{ background: '#1e2022' }}>{t('share.dialog.permFork')}</option>
              <option value="collaborate" style={{ background: '#1e2022' }}>{t('share.dialog.permCollab')}</option>
            </select>
          </div>

          {/* Strip Secrets Option */}
          <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer', fontSize: '12px', color: '#d1d5db' }}>
            <input
              type="checkbox"
              checked={stripSecrets}
              onChange={(e) => setStripSecrets(e.target.checked)}
              style={{ accentColor: '#10b981' }}
            />
            <span>{t('share.dialog.optStripSecrets')}</span>
          </label>

          {/* Copy or Generate Button */}
          {latestShareUrl ? (
            <div style={{ display: 'flex', gap: '6px' }}>
              <input
                type="text"
                readOnly
                value={latestShareUrl}
                style={{
                  flex: 1,
                  background: 'rgba(255, 255, 255, 0.04)',
                  border: '1px solid rgba(255, 255, 255, 0.1)',
                  borderRadius: '6px',
                  padding: '7px 10px',
                  color: '#60a5fa',
                  fontSize: '12px',
                  fontFamily: 'monospace',
                  outline: 'none',
                }}
              />
              <button
                type="button"
                onClick={handleCopy}
                style={{
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: '5px',
                  padding: '7px 14px',
                  borderRadius: '6px',
                  backgroundColor: copied ? 'rgba(16, 185, 129, 0.2)' : 'rgba(59, 130, 246, 0.2)',
                  border: '1px solid',
                  borderColor: copied ? '#10b981' : '#3b82f6',
                  color: copied ? '#34d399' : '#60a5fa',
                  fontSize: '12px',
                  fontWeight: 600,
                  cursor: 'pointer',
                  whiteSpace: 'nowrap',
                }}
              >
                {copied ? <IconCheckOutline14 size={13} /> : <IconCopyOutline16 size={13} />}
                <span>{copied ? t('share.dialog.copied') : t('share.dialog.copyLink')}</span>
              </button>
            </div>
          ) : (
            <button
              type="button"
              onClick={handleCreateShare}
              disabled={loading}
              style={{
                padding: '9px 14px',
                borderRadius: '6px',
                backgroundColor: '#2563eb',
                border: 'none',
                color: '#ffffff',
                fontSize: '13px',
                fontWeight: 600,
                cursor: 'pointer',
                transition: 'background 150ms ease',
              }}
            >
              {loading ? 'Creating...' : t('share.dialog.createLink')}
            </button>
          )}
        </div>

        {/* Active Links / Kill Switch List */}
        {activeShares.length > 0 && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', marginTop: '4px' }}>
            <div style={{ fontSize: '10px', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.05em', color: '#6b7280' }}>
              {t('share.dialog.existingLinks')}
            </div>
            {activeShares.map((s) => (
              <div
                key={s.shareId}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  padding: '6px 10px',
                  borderRadius: '6px',
                  backgroundColor: s.revoked ? 'rgba(239, 68, 68, 0.08)' : 'rgba(255, 255, 255, 0.02)',
                  border: '1px solid',
                  borderColor: s.revoked ? 'rgba(239, 68, 68, 0.2)' : 'rgba(255, 255, 255, 0.05)',
                  fontSize: '12px',
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <span
                    style={{
                      padding: '1px 6px',
                      borderRadius: '3px',
                      fontSize: '10px',
                      fontFamily: 'monospace',
                      backgroundColor: s.revoked ? 'rgba(239, 68, 68, 0.2)' : 'rgba(16, 185, 129, 0.2)',
                      color: s.revoked ? '#ef4444' : '#34d399',
                    }}
                  >
                    {s.revoked ? 'REVOKED' : s.scope}
                  </span>
                  <span style={{ color: '#9ca3af', fontFamily: 'monospace', fontSize: '11px' }}>
                    {s.token.slice(0, 18)}...
                  </span>
                </div>

                {!s.revoked && (
                  <button
                    type="button"
                    onClick={() => handleRevoke(s.shareId)}
                    style={{
                      background: 'none',
                      border: 'none',
                      color: '#ef4444',
                      cursor: 'pointer',
                      fontSize: '11px',
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: '4px',
                    }}
                  >
                    <IconTrashOutline16 size={13} />
                    <span>{t('share.dialog.revoke')}</span>
                  </button>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>,
    document.body
  );
}
