/** Localized strings for dsh-auth Settings and Group Switcher UI. */

export const zh = {
  'settings.auth.nav': '身份与访问',
  'settings.auth.title': '账户与身份凭证',
  'settings.auth.description': '当前登录租户的身份认证源、安全等级（Clearance）与 MTAA 访问策略。',
  'settings.auth.username': '当前用户',
  'settings.auth.clearance': '安全等级 (Clearance)',
  'settings.auth.provider': '认证源 (Provider)',
  'settings.auth.groups': '所属组 (Groups)',
  'settings.auth.lbacPolicy': 'Lattice-Based Access Control (LBAC)',
  'settings.auth.adminExplanation': '您具有最高的系统管理员级别（Admin），对所有系统工具和 Shell 拥有完全访问权限。',
  'settings.auth.restrictedExplanation': '当前处于受限级别（Restricted），受保护的系统级工具（Shell、Git Mutation、Rebuild）已被严格限制。',

  // Workspace / Group Switcher
  'group.switcher.personal': '个人空间',
  'group.switcher.group': '团队空间',
  'group.switcher.switchScope': '切换协作空间',
  'group.switcher.active': '当前激活',
  'group.switcher.role': '角色',

  // Session Share & Scope Action
  'session.share.action': '共享会话',
  'session.share.title': '会话访问范围',
  'session.share.description': '指定此会话在 MTAA 网格中的可见性与协作权限。',
  'session.share.scopePersonal': '私有（仅个人可见）',
  'session.share.scopeGroup': '群组协作（团队共享）',
  'session.share.scopePublic': '公开（租户全员可见）',
  'session.share.save': '更新权限',
  'session.share.current': '当前范围',
} satisfies Record<string, string>;

export type AuthSettingsKey = keyof typeof zh;

export const en = {
  'settings.auth.nav': 'Identity & Access',
  'settings.auth.title': 'Account & Identity',
  'settings.auth.description': 'Current tenant identity, clearance level, and MTAA access control policies.',
  'settings.auth.username': 'Current User',
  'settings.auth.clearance': 'Clearance Level',
  'settings.auth.provider': 'Auth Provider',
  'settings.auth.groups': 'User Groups',
  'settings.auth.lbacPolicy': 'Lattice-Based Access Control (LBAC)',
  'settings.auth.adminExplanation': 'You possess universal Admin clearance. Full access to system tools, execution, and rebuilds is granted.',
  'settings.auth.restrictedExplanation': 'You possess Restricted clearance. Execution of administrative shell tools and system mutations is restricted.',

  // Workspace / Group Switcher
  'group.switcher.personal': 'Personal',
  'group.switcher.group': 'Group',
  'group.switcher.switchScope': 'Switch Organization / Scope',
  'group.switcher.active': 'Active',
  'group.switcher.role': 'Role',

  // Session Share & Scope Action
  'session.share.action': 'Share',
  'session.share.title': 'Session Access Scope',
  'session.share.description': 'Designate visibility and collaborative capabilities across the MTAA lattice.',
  'session.share.scopePersonal': 'Private (Only you)',
  'session.share.scopeGroup': 'Group Collaboration (Shared)',
  'session.share.scopePublic': 'Public (All tenant members)',
  'session.share.save': 'Update Scope',
  'session.share.current': 'Current Scope',
} satisfies Record<AuthSettingsKey, string>;
