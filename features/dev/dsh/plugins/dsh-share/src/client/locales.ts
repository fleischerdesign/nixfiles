/** Localized strings for Universal Share Dialog. */

export const zh = {
  'share.dialog.title': '共享会话',
  'share.dialog.description': '通过安全签名链接公开分享快照，或指定团队/成员协同访问。',
  'share.dialog.peopleSection': '协作者与群组访问',
  'share.dialog.invitePlaceholder': '输入成员 (@alice) 或群组 (group:dev)...',
  'share.dialog.inviteButton': '邀请',
  'share.dialog.linkSection': '通用链接分享 (Link Sharing)',
  'share.dialog.scopeRestricted': '受限（仅限已授权人员）',
  'share.dialog.scopeGroup': '群组专享（群组成员凭身份访问）',
  'share.dialog.scopePublic': '公开快照（拥有链接者均可查看）',
  'share.dialog.permView': '仅查看',
  'share.dialog.permFork': '可查看并复刻 (Fork)',
  'share.dialog.permCollab': '完整协同 (Collaborate)',
  'share.dialog.optStripSecrets': '过滤环境密钥、API Keys 与私有系统路径 (推荐)',
  'share.dialog.copyLink': '复制链接',
  'share.dialog.copied': '已复制到剪贴板！',
  'share.dialog.createLink': '生成新链接',
  'share.dialog.existingLinks': '已生成的活跃链接',
  'share.dialog.revoke': '撤销链接',
  'share.dialog.expiresNever': '永不过期',
  'share.dialog.expiresIn': '有效期: {days} 天',
} satisfies Record<string, string>;

export type ShareLocaleKey = keyof typeof zh;

export const en = {
  'share.dialog.title': 'Share Session',
  'share.dialog.description': 'Share an immutable snapshot via secure signed link or designate group access.',
  'share.dialog.peopleSection': 'Collaborators & Groups',
  'share.dialog.invitePlaceholder': 'Add user (@alice) or group (group:dev)...',
  'share.dialog.inviteButton': 'Invite',
  'share.dialog.linkSection': 'General Access (Link Sharing)',
  'share.dialog.scopeRestricted': 'Restricted (Only designated people)',
  'share.dialog.scopeGroup': 'Group Only (Members of your group)',
  'share.dialog.scopePublic': 'Public Snapshot (Anyone with link can view)',
  'share.dialog.permView': 'Can view',
  'share.dialog.permFork': 'Can view & fork',
  'share.dialog.permCollab': 'Can collaborate',
  'share.dialog.optStripSecrets': 'Mask API keys, credentials, and paths (Recommended)',
  'share.dialog.copyLink': 'Copy Link',
  'share.dialog.copied': 'Link copied to clipboard!',
  'share.dialog.createLink': 'Create Link',
  'share.dialog.existingLinks': 'Active Share Links',
  'share.dialog.revoke': 'Revoke',
  'share.dialog.expiresNever': 'Never expires',
  'share.dialog.expiresIn': 'Expires in {days} days',
} satisfies Record<ShareLocaleKey, string>;
