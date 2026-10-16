// Refresh credentials in place: a token rotation must not navigate away from
// the current session or discard an unsent draft.
export async function refreshManagedRuntime({ readHosts, readUrl, readToken, setToken, refreshUrlToken, resume }) {
  const config = await readHosts();
  const normalize = value => String(value || '').replace(/\/+$/, '');
  const active = config.hosts.find(host => host.id.startsWith('nix:') && normalize(host.apiUrl || host.url) === normalize(readUrl()));
  if (!active?.clientToken || active.clientToken === readToken()) return false;
  const url = readUrl();
  const previous = readToken();
  setToken(active.clientToken);
  try {
    await refreshUrlToken(url);
  } catch (error) {
    // Retry on the next poll, without overwriting a concurrent host switch.
    if (normalize(readUrl()) === normalize(url) && readToken() === active.clientToken) setToken(previous);
    throw error;
  }
  if (normalize(readUrl()) === normalize(url)) resume();
  return true;
}
