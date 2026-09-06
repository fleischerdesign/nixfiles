import type { Context as ClientContext } from '@deepseek-ai/cordis';
import type {} from '@deepseek-ai/dsh-client-ui-slots';
import type {} from '@deepseek-ai/dsh-client-locale/client';
import type {} from '@deepseek-ai/dsh-client-ui-renderer/client';
import { UniversalShareModal } from './UniversalShareModal.js';
import { zh, en, type ShareLocaleKey } from './locales.js';

export { UniversalShareModal } from './UniversalShareModal.js';
export type { UniversalShareModalProps } from './UniversalShareModal.js';
export type { ShareLocaleKey } from './locales.js';

declare module '@deepseek-ai/dsh-client-ui-slots' {
  interface LocaleNamespaceMap {
    'session.share': ShareLocaleKey;
  }
}

const NS = 'session.share';

export const inject = ['slots', 'locale'];

export function apply(ctx: ClientContext): void {
  // Register localization dictionaries
  (ctx as any).effect(() => (ctx as any).locale.register(NS, { zh, en }), 'dsh-share: dictionaries');

  // Inject Universal Share Modal into sidebar.footer.action (mounts listener globally without taking visible space)
  (ctx as any).slots.inject('sidebar.footer.action', () => {
    (ctx as any).slots.register(
      {
        name: 'sidebar.footer.action',
        id: 'universal-share-modal-listener',
        order: 99,
        locale: NS,
      },
      UniversalShareModal
    );
  });
}
