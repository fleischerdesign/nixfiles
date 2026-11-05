"""Credential and agent-state path boundary.

Git ignore rules express build intent, not secrecy. This module refuses a
narrow set of credential and agent-state locations independently of them, so a
nonignored `.env` or private key cannot become build input. It is a name
boundary only: a semantically secret file under an ordinary name still leaves
the trust boundary at the executor account.
"""

FORBIDDEN_COMPONENTS = {
    ".openclaw",
    ".ssh",
    ".aws",
    ".gnupg",
    ".kube",
    ".docker",
    ".password-store",
}
FORBIDDEN_NAMES = {
    ".netrc",
    ".git-credentials",
    "credentials.json",
    "application_default_credentials.json",
    "kubeconfig",
    ".npmrc",
    ".pypirc",
}
FORBIDDEN_SUFFIXES = (".pem", ".key", ".p12", ".pfx", ".jks", ".keystore")
ENV_TEMPLATES = {".env.example", ".env.sample", ".env.template", ".env.dist"}


def forbidden_reason(rel: str) -> str | None:
    """Name the credential/agent-state rule a relative path violates, if any."""
    parts = rel.split("/")
    for part in parts:
        if part in FORBIDDEN_COMPONENTS:
            return f"credential or agent-state directory {part!r}"
    name = parts[-1]
    if name == ".env" or (name.startswith(".env.") and name not in ENV_TEMPLATES):
        return "dotenv file"
    if name in FORBIDDEN_NAMES:
        return "credential file"
    if name in {"id_rsa", "id_ed25519", "id_ecdsa", "id_dsa"}:
        return "SSH private key"
    if any(name.endswith(suffix) for suffix in FORBIDDEN_SUFFIXES):
        return "private key or keystore"
    return None
