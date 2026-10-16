// Nix supplies public intent separately from the mutable, private token cache.
// Read both on demand: reconciliation must also work while the desktop is open.
import fs from 'node:fs';

export const isManagedHost = host => typeof host?.id === 'string' && host.id.startsWith('nix:');

export function mergeManagedHosts(config, env = process.env) {
  if (!env.OPENCHAMBER_MANAGED_HOSTS_CONFIG) return config;
  let manifest = { hosts: [] };
  try {
    manifest = JSON.parse(fs.readFileSync(env.OPENCHAMBER_MANAGED_HOSTS_CONFIG, 'utf8'));
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  let credentials = { connections: {} };
  if (manifest.hosts.length > 0) try {
    credentials = JSON.parse(fs.readFileSync(env.OPENCHAMBER_MANAGED_HOSTS_STATE, 'utf8'));
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  const managed = manifest.hosts.map(host => {
    const cached = credentials.connections[host.name];
    return {
      id: `nix:${host.name}`, label: host.name, url: host.url, apiUrl: host.url,
      ...(cached?.url === host.url && cached.token ? { clientToken: cached.token } : {}),
    };
  });
  const urls = new Set(managed.map(host => host.url.replace(/\/+$/, '')));
  const hosts = [
    ...config.hosts.filter(host => !isManagedHost(host) && !urls.has(host.url?.replace(/\/+$/, ''))),
    ...managed,
  ];
  const defaultHostId = config.defaultHostId === 'local' || hosts.some(host => host.id === config.defaultHostId)
    ? config.defaultHostId : 'local';
  return { ...config, hosts, defaultHostId, initialHostChoiceCompleted: managed.length > 0 || config.initialHostChoiceCompleted };
}
