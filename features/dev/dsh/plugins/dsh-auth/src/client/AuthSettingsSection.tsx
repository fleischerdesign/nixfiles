import React, { useState, useEffect } from 'react';
import { fetchTenantIdentity, parseTenantIdentity } from './identity.js';
import type { AuthSettingsKey } from './locales.js';

export interface AuthSectionProps {
  close?: () => void;
  t?: (key: AuthSettingsKey) => string;
}

export function AuthSettingsSection({ t = (k: string) => k }: AuthSectionProps) {
  // The session cookie is HttpOnly, so identity must come from the server
  // endpoint (/auth/identity) rather than document.cookie.
  const [identity, setIdentity] = useState(() => parseTenantIdentity());

  useEffect(() => {
    let live = true;
    fetchTenantIdentity().then((id) => { if (live) setIdentity(id); });
    return () => { live = false; };
  }, []);

  const username = identity.username;
  const clearance = identity.clearance;
  const provider = identity.provider;
  const groups = identity.groups;

  const clearanceBadgeBg = clearance === 'Admin' ? 'rgba(16, 185, 129, 0.15)' : 'rgba(59, 130, 246, 0.15)';
  const clearanceBadgeColor = clearance === 'Admin' ? '#34d399' : '#60a5fa';

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '20px', maxWidth: '640px' }}>
      <div>
        <h3 style={{ margin: '0 0 4px 0', fontSize: '15px', fontWeight: 600, color: 'var(--dsw-alias-label-primary, #fff)' }}>
          {t('settings.auth.title')}
        </h3>
        <p style={{ margin: 0, fontSize: '12px', color: 'var(--dsw-alias-label-tertiary, #9ca3af)' }}>
          {t('settings.auth.description')}
        </p>
      </div>

      {/* Identity Card */}
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          gap: '12px',
          padding: '16px',
          borderRadius: '8px',
          backgroundColor: 'var(--dsw-alias-bg-secondary, rgba(255, 255, 255, 0.03))',
          border: '1px solid var(--dsw-alias-border-secondary, rgba(255, 255, 255, 0.08))',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <span style={{ fontSize: '13px', fontWeight: 500 }}>{t('settings.auth.username')}</span>
          <span style={{ fontSize: '13px', fontFamily: 'monospace', fontWeight: 600 }}>{username}</span>
        </div>

        <div style={{ height: '1px', backgroundColor: 'rgba(255, 255, 255, 0.06)' }} />

        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <span style={{ fontSize: '13px', fontWeight: 500 }}>{t('settings.auth.clearance')}</span>
          <span
            style={{
              padding: '2px 8px',
              borderRadius: '4px',
              backgroundColor: clearanceBadgeBg,
              color: clearanceBadgeColor,
              fontSize: '11px',
              fontFamily: 'monospace',
              fontWeight: 600,
              textTransform: 'uppercase',
              letterSpacing: '0.05em',
            }}
          >
            {clearance}
          </span>
        </div>

        <div style={{ height: '1px', backgroundColor: 'rgba(255, 255, 255, 0.06)' }} />

        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <span style={{ fontSize: '13px', fontWeight: 500 }}>{t('settings.auth.provider')}</span>
          <span style={{ fontSize: '12px', fontFamily: 'monospace', opacity: 0.8 }}>{provider}</span>
        </div>

        <div style={{ height: '1px', backgroundColor: 'rgba(255, 255, 255, 0.06)' }} />

        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <span style={{ fontSize: '13px', fontWeight: 500 }}>{t('settings.auth.groups')}</span>
          <span style={{ fontSize: '12px', fontFamily: 'monospace', opacity: 0.8 }}>{groups.join(', ')}</span>
        </div>
      </div>

      {/* MTAA Lattice Policy Overview */}
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          gap: '8px',
          padding: '14px 16px',
          borderRadius: '8px',
          backgroundColor: 'rgba(255, 255, 255, 0.02)',
          border: '1px solid rgba(255, 255, 255, 0.05)',
        }}
      >
        <div style={{ fontSize: '12px', fontWeight: 600, color: 'var(--dsw-alias-label-secondary, #d1d5db)' }}>
          {t('settings.auth.lbacPolicy')}
        </div>
        <div style={{ fontSize: '11px', color: 'var(--dsw-alias-label-tertiary, #9ca3af)', lineHeight: '1.5' }}>
          {clearance === 'Admin'
            ? t('settings.auth.adminExplanation')
            : t('settings.auth.restrictedExplanation')}
        </div>
      </div>
    </div>
  );
}
