import type { Context as ClientContext } from '@deepseek-ai/cordis';
import type {} from '@deepseek-ai/dsh-client-ui-slots';
import type {} from '@deepseek-ai/dsh-client-locale/client';
import type {} from '@deepseek-ai/dsh-client-ui-renderer/client';
import { ClusterSettingsSection } from './ClusterSettingsSection.js';
import { WorkspaceActionBanner } from './WorkspaceActionBanner.js';
import { zh, en, type ClusterSettingsKey } from './locales.js';

export { ClusterSettingsSection } from './ClusterSettingsSection.js';
export { WorkspaceActionBanner } from './WorkspaceActionBanner.js';
export type { ClusterSectionProps } from './ClusterSettingsSection.js';
export type { ClusterSettingsKey } from './locales.js';

declare module '@deepseek-ai/dsh-client-ui-slots' {
  interface LocaleNamespaceMap {
    'settings.cluster': ClusterSettingsKey;
  }
}

const NS = 'settings.cluster';

export const inject = ['slots', 'locale'];

export function apply(ctx: ClientContext): void {
  // Register localization dictionaries
  (ctx as any).effect(() => (ctx as any).locale.register(NS, { zh, en }), 'dsh-mesh: dictionaries');

  const t = (ctx as any).locale?.bind(NS) || ((k: string) => k);

  // Inject Cluster section into the Settings modal
  (ctx as any).slots.inject('settings.section', () => {
    (ctx as any).slots.register({
      name: 'settings.section',
      id: 'cluster',
      order: 45,
      locale: NS,
      label: () => t('settings.cluster.nav'),
    }, ClusterSettingsSection);
  });

  // Inject Workspace Action Banner above the Composer
  (ctx as any).slots.inject('conversation.composer.dock', () => {
    (ctx as any).slots.register({
      name: 'conversation.composer.dock',
      id: 'mesh-workspace-action',
      order: 10,
    }, WorkspaceActionBanner);
  });
}
