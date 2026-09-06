import type { Context as ClientContext } from '@deepseek-ai/cordis';
import type {} from '@deepseek-ai/dsh-client-ui-slots';
import type {} from '@deepseek-ai/dsh-client-locale/client';
import type {} from '@deepseek-ai/dsh-client-ui-renderer/client';
import { AuthSettingsSection } from './AuthSettingsSection.js';
import { GroupWorkspaceSwitcher } from './GroupWorkspaceSwitcher.js';
import { SessionShareAction } from './SessionShareAction.js';
import { zh, en, type AuthSettingsKey } from './locales.js';

export { AuthSettingsSection } from './AuthSettingsSection.js';
export { GroupWorkspaceSwitcher } from './GroupWorkspaceSwitcher.js';
export { SessionShareAction } from './SessionShareAction.js';
export type { AuthSectionProps } from './AuthSettingsSection.js';
export type { GroupWorkspaceSwitcherProps } from './GroupWorkspaceSwitcher.js';
export type { SessionShareActionProps } from './SessionShareAction.js';
export type { AuthSettingsKey } from './locales.js';

declare module '@deepseek-ai/dsh-client-ui-slots' {
  interface LocaleNamespaceMap {
    'settings.auth': AuthSettingsKey;
  }
}

const NS = 'settings.auth';

export const inject = ['slots', 'locale'];

export function apply(ctx: ClientContext): void {
  // Register localization dictionaries
  (ctx as any).effect(() => (ctx as any).locale.register(NS, { zh, en }), 'dsh-auth: dictionaries');

  const t = (ctx as any).locale?.bind(NS) || ((k: string) => k);

  // 1. Inject Account & Identity into the Settings modal
  (ctx as any).slots.inject('settings.section', () => {
    (ctx as any).slots.register(
      {
        name: 'settings.section',
        id: 'auth-identity',
        order: 35,
        locale: NS,
        label: () => t('settings.auth.nav'),
      },
      AuthSettingsSection
    );
  });

  // 2. Inject Top-Left Workspace & Group Switcher into sidebar.brand.name
  (ctx as any).slots.inject('sidebar.brand.name', () => {
    (ctx as any).slots.register(
      {
        name: 'sidebar.brand.name',
        priority: 10,
        locale: NS,
      },
      GroupWorkspaceSwitcher
    );
  });

}
