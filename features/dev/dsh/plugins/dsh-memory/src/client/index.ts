import type { Context as ClientContext } from '@deepseek-ai/cordis';
import type {} from '@deepseek-ai/dsh-client-ui-slots';
import type {} from '@deepseek-ai/dsh-client-locale/client';
import type {} from '@deepseek-ai/dsh-client-ui-renderer/client';
import { KnowledgeSettingsSection } from './KnowledgeSettingsSection.js';
import { zh, en, type KnowledgeSettingsKey } from './locales.js';

export { KnowledgeSettingsSection } from './KnowledgeSettingsSection.js';
export type { KnowledgeSectionProps } from './KnowledgeSettingsSection.js';
export type { KnowledgeSettingsKey } from './locales.js';

declare module '@deepseek-ai/dsh-client-ui-slots' {
  interface LocaleNamespaceMap {
    'settings.knowledge': KnowledgeSettingsKey;
  }
}

const NS = 'settings.knowledge';

export const inject = ['slots', 'locale'];

export function apply(ctx: ClientContext): void {
  // Register localization dictionaries
  (ctx as any).effect(() => (ctx as any).locale.register(NS, { zh, en }), 'dsh-memory: dictionaries');

  const t = (ctx as any).locale?.bind(NS) || ((k: string) => k);

  // Inject Knowledge section into the Settings modal
  (ctx as any).slots.inject('settings.section', () => {
    (ctx as any).slots.register({
      name: 'settings.section',
      id: 'knowledge',
      order: 40,
      locale: NS,
      label: () => t('settings.knowledge.nav'),
    }, KnowledgeSettingsSection);
  });
}
