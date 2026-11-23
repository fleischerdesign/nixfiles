"""Push a server client token to every declared desktop.

The server is the authority: it mints one token per desktop and delivers it over the SSH path the
fleet already has (server -> desktop as the primary user). The desktop helper writes it into its
settings; tokens never appear in process arguments or logs.
"""

import json
import subprocess
import sys
from pathlib import Path

from server_enroll import issue


def push(port, password_path, plan):
    host = plan['host']
    for name, desktop in plan.get('desktops', {}).items():
        try:
            token = issue(port, password_path, name)['clientToken']
        except Exception as error:
            print(f'OpenChamber token for {name} failed ({type(error).__name__})', file=sys.stderr)
            continue
        command = 'bash -lc ' + shell_quote(
            'exec openchamber-fleet-pair --set-server-token ' + host)
        result = subprocess.run(
            ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5',
             '-p', str(desktop['sshPort']), desktop['user'] + '@' + desktop['address'], command],
            input=token, capture_output=True, text=True, timeout=30,
        )
        if result.returncode:
            print(f'OpenChamber token push to {name} failed', file=sys.stderr)
        else:
            print(f'OpenChamber server token delivered to {name}')


def shell_quote(value):
    return "'" + value.replace("'", "'\\''") + "'"


if __name__ == '__main__':
    try:
        port = int(sys.argv[1])
        password_path = sys.argv[2]
        plan = json.loads(Path(sys.argv[3]).read_text())
        push(port, password_path, plan)
    except Exception as error:
        print(f'OpenChamber server push failed ({type(error).__name__})', file=sys.stderr)
        sys.exit(1)
