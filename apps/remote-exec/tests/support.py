import os
import shutil
import subprocess
import tempfile
import unittest


class RepoFixture(unittest.TestCase):
    """A real Git repository in a temporary directory, with a fixed identity."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="remote-exec-test-")
        self.repo = os.path.join(self.tmp, "repo")
        os.makedirs(self.repo)
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        self.env = dict(os.environ)
        self.env.update(
            {
                "HOME": self.home,
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_AUTHOR_NAME": "Test",
                "GIT_AUTHOR_EMAIL": "test@example.invalid",
                "GIT_COMMITTER_NAME": "Test",
                "GIT_COMMITTER_EMAIL": "test@example.invalid",
            }
        )
        self.git("init", "-q")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.invalid")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def git(self, *args):
        return subprocess.run(
            ["git", "-C", self.repo, *args],
            env=self.env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        ).stdout

    def write(self, rel, content, mode=None):
        path = os.path.join(self.repo, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as handle:
            handle.write(content if isinstance(content, bytes) else content.encode())
        if mode is not None:
            os.chmod(path, mode)
        return path

    def commit(self, message="commit"):
        self.git("add", "-A")
        return self.git("-c", "commit.gpgsign=false", "commit", "-qm", message)

    def out(self, name="capture"):
        return os.path.join(self.tmp, name)
