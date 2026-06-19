"""
Custom Robot Framework library for runtime validation.
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
        """Infer the containerlab topology name from the project directory."""
        return self.project_dir.name

    # -- lab lifecycle -----------------------------------------------------------

    def netlab_up(self, timeout=300):
        """Run `netlab up` to start the lab.

        Args:
            timeout: Maximum time in seconds to wait.

        Returns:
            (rc, stdout, stderr) tuple.
        """
        cmd = ['netlab', 'up', '--log']
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=str(self.project_dir)
        )
        return result.returncode, result.stdout, result.stderr

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

        The command is passed WITHOUT the 'show' prefix — netlab adds it.

        Args:
            node: Device name (e.g. spine1).
            command: Show command body (e.g. 'isis neighbors').

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
        cmd = ['netlab', 'connect', node] + list(args)
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
            cwd=str(self.project_dir)
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
            command: Multi-line command string with embedded newlines
                     (e.g. 'configure\\ninterface Eth1\\nshutdown\\nend').

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
        # Parse: DRY RUN: ['sshpass', '-p', 'admin', 'ssh', ...]
        # Extract the SSH command parts (skip 'DRY RUN: ')
        line = dry_run.stdout.strip()
        # Parse the list representation
        import ast
        cmd_str = line.split(':', 1)[1].strip()
        ssh_cmd = ast.literal_eval(cmd_str)

        # Append -t for pseudo-terminal (needed for multiline commands)
        # Insert after 'ssh'
        ssh_cmd.insert(ssh_cmd.index('ssh') + 1, '-t')
        # Append the multiline command
        ssh_cmd.append(command)

        result = subprocess.run(
            ssh_cmd,
            capture_output=True,
            text=True,
            timeout=60
        )
        return result.stdout.strip()

    # -- packet capture ----------------------------------------------------------

    def get_container_name(self, node):
        """Return the containerlab container name for a node."""
        return f'clab-{self.topology_name}-{node}'

    def capture_packets(self, node, interface, bpf_filter, count, timeout=30):
        """Capture packets on a node interface using docker exec + tcpdump.

        Why docker exec instead of `netlab capture`?
        `netlab capture` runs `sudo ip netns exec` which requires interactive
        sudo password input — not suitable for automated headless tests.
        `docker exec` works without sudo and is non-blocking.

        The container name is derived from the topology directory name:
            clab-{topology_name}-{node}

        Args:
            node: Device name (e.g. spine1).
            interface: Interface name in containerlab (e.g. et1).
            bpf_filter: BPF filter expression.
            count: Number of packets to capture.
            timeout: Max wait time in seconds.

        Returns:
            Parsed packet descriptions from tcpdump -r (one line per packet).
        """
        container = self.get_container_name(node)
        pcap_path = f'/tmp/netlab_test_{int(time.time())}.pcap'
        capture_cmd = [
            'docker', 'exec', container, 'bash', '-c',
            f'tcpdump -i {interface} -c {count} -w {pcap_path} "{bpf_filter}"'
        ]
        proc = subprocess.Popen(
            capture_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        try:
            proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            proc.kill()
            raise TimeoutError(
                f'Packet capture timed out after {timeout}s on {node}/{interface}'
            )

        read_cmd = [
            'docker', 'exec', container, 'bash', '-c',
            f'tcpdump -r {pcap_path} -nn 2>/dev/null'
        ]
        result = subprocess.run(read_cmd, capture_output=True, text=True, timeout=15)
        return result.stdout.strip()

    def capture_packets_verbose(self, node, interface, bpf_filter, count, timeout=30, src_mac=None):
        """Capture packets with verbose tcpdump output.

        Args:
            src_mac: Optional source MAC address to filter only outgoing
                     packets from this host (e.g. 'ca:f0:00:01:00:01').
                     Prepends 'ether src <mac> and' to the BPF filter.

        Same other args as capture_packets. Returns verbose output with TLV details.
        """
        container = self.get_container_name(node)
        pcap_path = f'/tmp/netlab_test_v_{int(time.time())}.pcap'
        if src_mac:
            bpf_filter = f'ether src {src_mac} and {bpf_filter}'
        capture_cmd = [
            'docker', 'exec', container, 'bash', '-c',
            f'tcpdump -i {interface} -c {count} -w {pcap_path} "{bpf_filter}"'
        ]
        proc = subprocess.Popen(
            capture_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        try:
            proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            proc.kill()
            raise TimeoutError(
                f'Packet capture timed out after {timeout}s on {node}/{interface}'
            )

        read_cmd = [
            'docker', 'exec', container, 'bash', '-c',
            f'tcpdump -r {pcap_path} -nn -v 2>/dev/null'
        ]
        result = subprocess.run(read_cmd, capture_output=True, text=True, timeout=15)
        return result.stdout.strip()
