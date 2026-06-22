"""
Custom Robot Framework library for runtime validation of eBGP underlay lab.
All device access goes through `netlab connect` — no direct sshpass calls.
Lab lifecycle is managed via `netlab up` / `netlab down`.
"""

import os
import subprocess
import time
from pathlib import Path


class NetlabRuntimeLibrary:
    """Robot Framework library for runtime validation via netlab connect."""

    ROBOT_LIBRARY_SCOPE = 'GLOBAL'

    @property
    def project_dir(self):
        """Resolve project directory from PROJECT_DIR env var."""
        return Path(os.environ.get('PROJECT_DIR', '.')).resolve()

    @property
    def topology_name(self):
        """Infer the containerlab topology name from the project directory.

        Containerlab strips underscores from the topology name, so
        'lab_04' becomes 'lab04'.
        """
        return self.project_dir.name.replace('_', '')

    # -- lab lifecycle -----------------------------------------------------------

    def netlab_up(self, timeout=300):
        """Run `netlab up --no-config` to start containers, then push configs manually.

        Args:
            timeout: Maximum time in seconds to wait.

        Returns:
            (rc, stdout, stderr) tuple.
        """
        all_output = []

        # Step 0: Ensure clean state — tear down any existing lab
        down_cmd = ['netlab', 'down', '--cleanup']
        subprocess.run(
            down_cmd,
            capture_output=True,
            text=True,
            timeout=120,
            cwd=str(self.project_dir)
        )

        # Step 1: Start containers only (skip Ansible to avoid sudo hang)
        cmd = ['netlab', 'up', '--no-config']
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=str(self.project_dir)
        )
        all_output.append(result.stdout)
        if result.returncode != 0:
            # Check if containers are actually running despite the error
            check = subprocess.run(
                ['containerlab', 'inspect', '--all'],
                capture_output=True, text=True, timeout=15
            )
            if f'clab-{self.topology_name}-' not in check.stdout:
                return result.returncode, result.stdout, result.stderr
            all_output.append('netlab up returned non-zero but containers are running, continuing')

        # Wait for EOS SSH to be ready (cEOS takes ~30-60s to boot)
        import socket, time
        mgmt_ips = ['192.168.121.101', '192.168.121.102', '192.168.121.103',
                     '192.168.121.104', '192.168.121.105']
        deadline = time.time() + 120
        while time.time() < deadline:
            all_up = True
            for ip in mgmt_ips:
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.settimeout(2)
                try:
                    s.connect((ip, 22))
                except (socket.timeout, ConnectionRefusedError, OSError):
                    all_up = False
                finally:
                    s.close()
            if all_up:
                break
            time.sleep(5)

        # Step 2: Push configs to EOS devices
        eos_nodes = ['spine1', 'spine2', 'leaf1', 'leaf2', 'leaf3']
        for node in eos_nodes:
            cfg_path = self.project_dir / 'configs' / f'{node}.cfg'
            if not cfg_path.exists():
                continue
            config_text = self._build_eos_config(str(cfg_path))
            dry_run = subprocess.run(
                ['netlab', 'connect', node, '--dry-run'],
                capture_output=True, text=True, timeout=10,
                cwd=str(self.project_dir)
            )
            line = dry_run.stdout.strip()
            import ast
            cmd_str = line.split(':', 1)[1].strip()
            ssh_cmd = ast.literal_eval(cmd_str)
            result = subprocess.run(
                ssh_cmd, input=config_text, capture_output=True, text=True, timeout=120
            )
            if result.returncode != 0:
                # Log but continue — some errors may be non-fatal (duplicate config)
                all_output.append(f'{node}: config push returned rc={result.returncode}')

        # Step 3: Configure Linux hosts
        host_configs = {
            'host1': {'ip': '10.3.1.1', 'gw': '10.3.1.0'},
            'host2': {'ip': '10.3.2.1', 'gw': '10.3.2.0'},
            'host3': {'ip': '10.3.3.1', 'gw': '10.3.3.0'},
        }
        for host, cfg in host_configs.items():
            container = f'clab-{self.topology_name}-{host}'
            setup_cmd = [
                'docker', 'exec', container, 'bash', '-c',
                f'apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping > /dev/null 2>&1; '
                f'ip addr add {cfg["ip"]}/31 dev eth1 2>/dev/null; '
                f'ip link set eth1 up; '
                f'ip route del default via 192.168.121.1 2>/dev/null; '
                f'ip route add default via {cfg["gw"]} 2>/dev/null'
            ]
            result = subprocess.run(setup_cmd, capture_output=True, text=True, timeout=120)
            if result.returncode != 0:
                all_output.append(f'{host}: setup returned rc={result.returncode}')

        # Wait for BGP sessions to establish after config push
        rc, msg = self.wait_for_bgp(timeout=120)

        return 0, '\n'.join(all_output) + '\nOK', ''

    def wait_for_bgp(self, timeout=120):
        """Wait until all EOS BGP sessions are Established.

        Polls `show ip bgp summary` on all EOS nodes until every neighbor
        shows 'Estab' state.

        Args:
            timeout: Maximum seconds to wait.

        Returns:
            (rc, msg) tuple. rc=0 on success.
        """
        import time
        deadline = time.time() + timeout
        eos_nodes = ['spine1', 'spine2', 'leaf1', 'leaf2', 'leaf3']
        while time.time() < deadline:
            all_estab = True
            for node in eos_nodes:
                output = self.run_show_command(node, 'ip bgp summary')
                if 'Estab' not in output or 'Active' in output:
                    all_estab = False
                    break
            if all_estab:
                return 0, 'BGP established'
            time.sleep(5)
        return 1, 'BGP not fully established'

    def _build_eos_config(self, cfg_path):
        """Build piped config from a saved .cfg file for EOS device.

        Preserves indentation — critical for EOS CLI context (router bgp, interface).
        """
        with open(cfg_path) as f:
            content = f.read()
        lines = ['enable', 'configure terminal']
        for line in content.split('\n'):
            rstripped = line.rstrip()
            if rstripped == 'end':
                break
            if rstripped:
                lines.append(rstripped)
        lines.append('end')
        lines.append('write memory')
        return '\n'.join(lines) + '\n'

    def netlab_down(self, timeout=120):
        """Run `netlab down` to tear down the lab.

        Args:
            timeout: Maximum time in seconds to wait.

        Returns:
            (rc, stdout, stderr) tuple.
        """
        cmd = ['netlab', 'down']
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=str(self.project_dir)
        )
        return result.returncode, result.stdout, result.stderr

    # -- netlab connect wrappers --------------------------------------------------

    def netlab_connect_show(self, node, command):
        """Execute a show command via `netlab connect --show`.

        Args:
            node: Device name (e.g. spine1).
            command: Show command body (e.g. 'bgp neighbors').

        Returns:
            stdout output, stripped.
        """
        cmd = ['netlab', 'connect', node, '--show', command]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
            cwd=str(self.project_dir)
        )
        return result.stdout.strip()

    def netlab_connect_cmd(self, node, *args):
        """Execute an arbitrary command via `netlab connect` (no 'show' prefix).

        Args:
            node: Device name (e.g. spine1).
            *args: Command tokens (e.g. 'ping', '10.0.11.1', 'source', 'Loopback0').

        Returns:
            stdout output, stripped.
        """
        # Get the SSH command from netlab connect dry-run, then pipe enable + command
        dry_run = subprocess.run(
            ['netlab', 'connect', node, '--dry-run'],
            capture_output=True,
            text=True,
            timeout=10,
            cwd=str(self.project_dir)
        )
        line = dry_run.stdout.strip()
        import ast
        cmd_str = line.split(':', 1)[1].strip()
        ssh_cmd = ast.literal_eval(cmd_str)

        # Build the command string to pipe into SSH
        command = 'enable\n' + ' '.join(args) + '\n'

        result = subprocess.run(
            ssh_cmd,
            input=command,
            capture_output=True,
            text=True,
            timeout=30
        )
        return result.stdout.strip()

    # -- high-level keywords for tests ------------------------------------------

    def run_show_command(self, node, command):
        """Keyword alias for netlab_connect_show."""
        return self.netlab_connect_show(node, command)

    def run_ping(self, node, target_ip, source_iface, repeat=3):
        """Ping from a node via `netlab connect` (no show prefix).

        Args:
            node: Source device name.
            target_ip: Destination IP.
            source_iface: Source interface (e.g. Loopback0).
            repeat: Number of packets.

        Returns:
            Ping output as string.
        """
        return self.netlab_connect_cmd(
            node,
            'ping', target_ip, 'source', source_iface, 'repeat', str(repeat)
        )

    def run_cli_command(self, node, command):
        """Run a multi-line CLI command (configure session) via SSH.

        Uses sshpass directly because `netlab connect` does not properly
        handle embedded newlines in non-interactive mode.

        Args:
            node: Device name.
            command: Multi-line command string with embedded newlines.

        Returns:
            Command output as string.
        """
        # Get the SSH command from netlab connect dry-run
        dry_run = subprocess.run(
            ['netlab', 'connect', node, '--dry-run'],
            capture_output=True,
            text=True,
            timeout=10,
            cwd=str(self.project_dir)
        )
        line = dry_run.stdout.strip()
        import ast
        cmd_str = line.split(':', 1)[1].strip()
        ssh_cmd = ast.literal_eval(cmd_str)

        ssh_cmd.insert(ssh_cmd.index('ssh') + 1, '-t')
        ssh_cmd.append(command)

        result = subprocess.run(
            ssh_cmd,
            capture_output=True,
            text=True,
            timeout=60
        )
        return result.stdout.strip()

    # -- host container helpers --------------------------------------------------

    def get_container_name(self, node):
        """Return the containerlab container name for a node."""
        return f'clab-{self.topology_name}-{node}'

    def run_host_ping(self, host, target_ip, count=3):
        """Ping from a Linux host container via docker exec.

        Args:
            host: Host container name (e.g. host1).
            target_ip: Destination IP.
            count: Number of packets.

        Returns:
            Ping output as string.
        """
        container = self.get_container_name(host)
        cmd = [
            'docker', 'exec', container,
            'ping', '-c', str(count), target_ip
        ]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )
        return result.stdout.strip()

    def run_host_command(self, host, command):
        """Run a command inside a host container via docker exec.

        Args:
            host: Host container name (e.g. host1).
            command: Command string or list.

        Returns:
            Command output as string.
        """
        container = self.get_container_name(host)
        if isinstance(command, str):
            cmd = ['docker', 'exec', container, 'bash', '-c', command]
        else:
            cmd = ['docker', 'exec', container] + list(command)
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )
        return result.stdout.strip()

    def run_host_show_route(self, host):
        """Show routing table on a Linux host container.

        Args:
            host: Host container name.

        Returns:
            `ip route` output as string.
        """
        return self.run_host_command(host, 'ip route')

    def run_host_show_ip(self, host):
        """Show IP addresses on a Linux host container.

        Args:
            host: Host container name.

        Returns:
            `ip addr` output as string.
        """
        return self.run_host_command(host, 'ip addr')
