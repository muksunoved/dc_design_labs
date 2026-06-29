"""
Custom Robot Framework library for runtime validation of VXLAN EVPN overlay lab.
All device access goes through `netlab connect` — no direct sshpass calls.
Lab lifecycle is managed via `netlab up` / `netlab down`.

PROJECT_DIR should point to the lab root (where configs/ lives), not the netlab/ subdirectory.
The netlab/ subdirectory is used as cwd for all `netlab` CLI commands.
"""

import os
import subprocess
import time
from pathlib import Path
import yaml

SETUP_README_URL = (
    "https://github.com/muksunoved/dc_design_labs/blob/main/source/setup/README.md"
    "#запуск-в-режиме-password-free-containerlab-для-тестов-rotot-framework"
)


class NetlabRuntimeLibrary:
    """Robot Framework library for runtime validation via netlab connect."""

    ROBOT_LIBRARY_SCOPE = 'GLOBAL'

    def __init__(self):
        """Initialize and load IP plan from ip-plan.yml."""
        self._ip_plan = None

    def load_ip_plan(self):
        """Load IP plan from ip-plan.yml and return as dictionary.

        Returns:
            Dictionary with structure:
            - loopback_ips: {node: ip_with_prefix}
            - vtep_ips: {node: ip_without_prefix}
            - host_overlay_ips: {host: ip_without_prefix}
            - neighbors: {node: [remote_ips]}
            - overlay: {vlan, vni, rt, subnet}
        """
        ip_plan_path = self.project_dir / 'netlab' / 'ip-plan.yml'
        with open(ip_plan_path) as f:
            ip_plan = yaml.safe_load(f)

        result = {
            'loopback_ips': {},
            'vtep_ips': {},
            'host_overlay_ips': {},
            'neighbors': {},
            'overlay': {}
        }

        # Extract loopback and neighbor IPs
        for node, data in ip_plan.items():
            if node == 'overlay':
                continue

            if 'loopback' in data:
                result['loopback_ips'][node] = data['loopback']
                # VTEP IPs are loopback without prefix
                if node.startswith('leaf'):
                    vtep_ip = data['loopback'].split('/')[0]
                    result['vtep_ips'][node] = vtep_ip

            if 'links' in data:
                result['neighbors'][node] = []
                for peer, link_data in data['links'].items():
                    if 'remote' in link_data:
                        result['neighbors'][node].append(link_data['remote'])

        # Extract overlay parameters
        if 'overlay' in ip_plan:
            overlay = ip_plan['overlay']

            if 'vlans' in overlay:
                for vlan_id, vlan_data in overlay['vlans'].items():
                    result['overlay']['vlan'] = vlan_id
                    result['overlay']['vni'] = vlan_data.get('vni')
                    result['overlay']['rt'] = vlan_data.get('rt')
                    result['overlay']['subnet'] = vlan_data.get('subnet')
                    break

            if 'hosts' in overlay:
                for host, ip_with_prefix in overlay['hosts'].items():
                    ip_without_prefix = ip_with_prefix.split('/')[0]
                    result['host_overlay_ips'][host] = ip_without_prefix

        self._ip_plan = result
        return result

    def get_ip_plan_variable(self, category, key=None):
        """Get specific value from loaded IP plan.

        Args:
            category: 'loopback_ips', 'vtep_ips', 'host_overlay_ips', 'neighbors', 'overlay'
            key: Optional key within category

        Returns:
            Value or entire category dict if key is None
        """
        if self._ip_plan is None:
            self.load_ip_plan()

        if category not in self._ip_plan:
            raise KeyError(f"Unknown IP plan category: {category}")

        if key is None:
            return self._ip_plan[category]

        if key not in self._ip_plan[category]:
            raise KeyError(f"Key '{key}' not found in category '{category}'")

        return self._ip_plan[category][key]

    def get_loopback_ips(self):
        """Return loopback_ips as flat list [node, ip, ...] for EOS nodes only."""
        if self._ip_plan is None:
            self.load_ip_plan()
        result = []
        for k, v in self._ip_plan['loopback_ips'].items():
            if k.startswith(('spine', 'leaf')):
                result.extend([k, v])
        return result

    def get_vtep_ips(self):
        """Return vtep_ips as flat list [node, ip, node, ip, ...] for RF FOR iteration."""
        if self._ip_plan is None:
            self.load_ip_plan()
        result = []
        for k, v in self._ip_plan['vtep_ips'].items():
            result.extend([k, v])
        return result

    def get_spine_neighbors(self, spine):
        """Return list of neighbor IPs for a spine node."""
        if self._ip_plan is None:
            self.load_ip_plan()
        return self._ip_plan['neighbors'].get(spine, [])

    def check_rootless_prerequisites(self):
        """Verify that the current user can run containerlab without sudo.

        Checks:
        1. User is in 'docker' and 'clab_admins' groups
        2. 'containerlab' binary has setuid bit
        3. 'netlab' is configured to run containerlab without sudo

        Raises AssertionError with a link to setup/README.md if any check fails.
        """
        import grp
        import shutil
        import stat

        errors = []

        # 1. Check groups
        username = os.environ.get('USER', os.path.basename(os.path.expanduser('~')))
        try:
            user_groups = [g.gr_name for g in grp.getgrall() if username in g.gr_mem]
        except Exception:
            user_groups = []

        for required_group in ('docker', 'clab_admins'):
            if required_group not in user_groups:
                errors.append(
                    f"User '{username}' is not in group '{required_group}'. "
                    f"Run: sudo usermod -aG {required_group} $USER && newgrp {required_group}"
                )

        # 2. Check setuid bit on containerlab
        clab_path = shutil.which('containerlab')
        if clab_path:
            mode = os.stat(clab_path).st_mode
            if not (mode & stat.S_ISUID):
                errors.append(
                    f"containerlab ({clab_path}) does not have setuid bit. "
                    f"Run: sudo chmod u+s $(command -v containerlab)"
                )
        else:
            errors.append("containerlab binary not found in PATH")

        # 3. Check netlab defaults for rootless operation
        netlab_start = subprocess.run(
            ['netlab', 'show', 'defaults', 'providers.clab.start'],
            capture_output=True, text=True, timeout=10
        ).stdout.strip()
        if 'sudo' in netlab_start or 'containerlab deploy' not in netlab_start:
            errors.append(
                "netlab is configured to use sudo for containerlab. "
                "Run:\n"
                "  netlab defaults --user providers.clab.start='containerlab deploy --reconfigure -t clab.yml'\n"
                "  netlab defaults --user providers.clab.stop='containerlab destroy --cleanup -t clab.yml'"
            )

        if errors:
            msg = (
                "Rootless containerlab prerequisites not met:\n"
                + "\n".join(f"  • {e}" for e in errors)
                + f"\n\nSee setup guide: {SETUP_README_URL}"
            )
            raise AssertionError(msg)

    @property
    def project_dir(self):
        """Resolve project directory from PROJECT_DIR env var.

        This is the lab root — the directory containing configs/, netlab/, tests/.
        """
        return Path(os.environ.get('PROJECT_DIR', '.')).resolve()

    @property
    def netlab_dir(self):
        """Directory containing topology.yml — used as cwd for netlab CLI commands."""
        return self.project_dir / 'netlab'

    @property
    def topology_name(self):
        """Infer the containerlab topology name.

        Netlab generates the containerlab topology in the netlab/ subdirectory,
        so the topology name comes from that directory (e.g. 'netlab'), not from
        the project directory name (e.g. 'lab_05' → 'lab05').
        """
        # If netlab dir exists and has topology.yml, use its directory name
        nl_dir = self.project_dir / 'netlab'
        if (nl_dir / 'topology.yml').exists():
            return nl_dir.name
        # Fallback: use project dir name with underscores stripped
        return self.project_dir.name.replace('_', '')

    # -- lab lifecycle -----------------------------------------------------------

    def netlab_up(self, timeout=300):
        """Run `netlab up --no-config` to start containers, then push configs manually.

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
            cwd=str(self.netlab_dir)
        )

        # Step 1: Start containers only (skip Ansible to avoid sudo hang)
        cmd = ['netlab', 'up', '--no-config']
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=str(self.netlab_dir)
        )
        all_output.append(result.stdout)
        if result.returncode != 0:
            check = subprocess.run(
                ['containerlab', 'inspect', '--all'],
                capture_output=True, text=True, timeout=15
            )
            if f'clab-{self.topology_name}-' not in check.stdout:
                return result.returncode, result.stdout, result.stderr
            all_output.append('netlab up returned non-zero but containers are running, continuing')

        # Wait for EOS SSH to be ready
        import socket
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
                cwd=str(self.netlab_dir)
            )
            line = dry_run.stdout.strip()
            import ast
            cmd_str = line.split(':', 1)[1].strip()
            ssh_cmd = ast.literal_eval(cmd_str)
            result = subprocess.run(
                ssh_cmd, input=config_text, capture_output=True, text=True, timeout=120
            )
            if result.returncode != 0:
                all_output.append(f'{node}: config push returned rc={result.returncode}')

        # Step 3: Ensure Linux host interfaces are up and have overlay IPs.
        # Host startup scripts install iproute2 via apt-get, but that can take 30-60s.
        # We install it here directly to avoid waiting for the startup script.
        host_configs = {
            'host1': {'ip': '192.168.10.11', 'prefix': '24', 'iface': 'eth1'},
            'host2': {'ip': '192.168.10.12', 'prefix': '24', 'iface': 'eth1'},
            'host3': {'ip': '192.168.10.13', 'prefix': '24', 'iface': 'eth1'},
        }
        for host, cfg in host_configs.items():
            container = f'clab-{self.topology_name}-{host}'
            # Install iproute2 if 'ip' is not available
            check_ip = subprocess.run(
                ['docker', 'exec', container, 'which', 'ip'],
                capture_output=True, text=True, timeout=10
            )
            if check_ip.returncode != 0:
                subprocess.run(
                    ['docker', 'exec', container, 'apt-get', 'update', '-qq'],
                    capture_output=True, text=True, timeout=60
                )
                subprocess.run(
                    ['docker', 'exec', container, 'apt-get', 'install', '-y', '-qq',
                     'iproute2', 'iputils-ping'],
                    capture_output=True, text=True, timeout=60
                )
            # Assign overlay IP (idempotent — skip if already assigned)
            subprocess.run(
                ['docker', 'exec', container, 'ip', 'link', 'set', cfg['iface'], 'up'],
                capture_output=True, text=True, timeout=10
            )
            result = subprocess.run(
                ['docker', 'exec', container, 'ip', 'addr', 'add',
                 f'{cfg["ip"]}/{cfg["prefix"]}', 'dev', cfg['iface']],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode != 0 and 'exists' not in result.stderr.lower():
                all_output.append(f'{host}: addr add returned rc={result.returncode}: {result.stderr.strip()}')

        # Wait for BGP sessions to establish after config push
        rc, msg = self.wait_for_bgp(timeout=120)

        # Wait for EVPN sessions to establish
        rc, msg = self.wait_for_evpn(timeout=90)

        return 0, '\n'.join(all_output) + '\nOK', ''

    def wait_for_bgp(self, timeout=120):
        """Wait until all EOS BGP IPv4 sessions are Established."""
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

    def wait_for_evpn(self, timeout=90):
        """Wait until all BGP EVPN sessions are Established on spines."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            all_estab = True
            for node in ['spine1', 'spine2']:
                output = self.run_show_command(node, 'bgp evpn summary')
                if 'Estab' not in output:
                    all_estab = False
                    break
            if all_estab:
                return 0, 'EVPN established'
            time.sleep(5)
        return 1, 'EVPN not established'

    def _build_eos_config(self, cfg_path):
        """Build piped config from a saved .cfg file for EOS device."""
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
        """Run `netlab down` to tear down the lab."""
        cmd = ['netlab', 'down']
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=str(self.netlab_dir)
        )
        return result.returncode, result.stdout, result.stderr

    # -- netlab connect wrappers --------------------------------------------------

    def netlab_connect_show(self, node, command):
        """Execute a show command via `netlab connect --show`."""
        cmd = ['netlab', 'connect', node, '--show', command]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
            cwd=str(self.netlab_dir)
        )
        return result.stdout.strip()

    def netlab_connect_cmd(self, node, *args):
        """Execute an arbitrary command via `netlab connect`."""
        dry_run = subprocess.run(
            ['netlab', 'connect', node, '--dry-run'],
            capture_output=True,
            text=True,
            timeout=10,
            cwd=str(self.netlab_dir)
        )
        line = dry_run.stdout.strip()
        import ast
        cmd_str = line.split(':', 1)[1].strip()
        ssh_cmd = ast.literal_eval(cmd_str)

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
        """Ping from a node via `netlab connect`."""
        return self.netlab_connect_cmd(
            node,
            'ping', target_ip, 'source', source_iface, 'repeat', str(repeat)
        )

    def run_cli_command(self, node, command):
        """Run a multi-line CLI command via SSH."""
        dry_run = subprocess.run(
            ['netlab', 'connect', node, '--dry-run'],
            capture_output=True,
            text=True,
            timeout=10,
            cwd=str(self.netlab_dir)
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
        """Ping from a Linux host container via docker exec."""
        container = self.get_container_name(host)
        # Try ping first, fall back to arping if ping binary is missing
        cmd = [
            'docker', 'exec', container, 'ping', '-c', str(count), target_ip
        ]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode != 0 and 'not found' in result.stderr.lower():
            # ping not installed, try installing it
            install_cmd = ['docker', 'exec', container, 'apt-get', 'install', '-y', '-qq', 'iputils-ping']
            subprocess.run(install_cmd, capture_output=True, text=True, timeout=60)
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )
        return result.stdout.strip()

    def run_host_command(self, host, command):
        """Run a command inside a host container via docker exec."""
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
        """Show routing table on a Linux host container."""
        return self.run_host_command(host, 'ip route')

    def run_host_show_ip(self, host):
        """Show IP addresses on a Linux host container."""
        return self.run_host_command(host, 'ip addr')

    # -- packet capture ----------------------------------------------------------

    def capture_packets(self, node, interface, bpf_filter, count, timeout=30):
        """Capture packets on a node interface using docker exec + tcpdump.

        Uses docker exec instead of `netlab capture` because the latter requires
        interactive sudo password input, which is incompatible with headless tests.

        Args:
            node: Device name (e.g. leaf1, host1).
            interface: Interface name inside the container (et1, eth1, etc.).
                       Use 'any' to capture on all interfaces.
            bpf_filter: BPF filter expression (e.g. 'udp port 4789').
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
            capture_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
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
        """Capture packets with verbose tcpdump output (-v flag).

        Args:
            src_mac: Optional source MAC address filter — prepends
                     'ether src <mac> and' to the BPF filter.
            Other args same as capture_packets.

        Returns:
            Verbose packet descriptions with TLV details.
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
            capture_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
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

    def bounce_interface(self, node, interface, wait_down=5, wait_up=3):
        """Shutdown then no-shutdown an interface on an EOS node via SSH.

        Args:
            node: EOS device name (e.g. leaf1).
            interface: Interface name (e.g. Ethernet3).
            wait_down: Seconds to wait after shutdown.
            wait_up: Seconds to wait after no-shutdown.
        """
        cmd_down = f'configure\ninterface {interface}\nshutdown\nend'
        cmd_up = f'configure\ninterface {interface}\nno shutdown\nend'
        self.run_cli_command(node, cmd_down)
        time.sleep(wait_down)
        self.run_cli_command(node, cmd_up)
        time.sleep(wait_up)

    # -- EVPN-specific helpers ---------------------------------------------------

    def run_evpn_show(self, node, command):
        """Execute an EVPN show command via `netlab connect --show`.

        Args:
            node: Device name (e.g. spine1, leaf1).
            command: EVPN command body (e.g. 'bgp evpn summary').

        Returns:
            stdout output, stripped.
        """
        return self.run_show_command(node, command)

    def get_evpn_route_count(self, node):
        """Count the number of EVPN routes on a node.

        Returns:
            Integer count of EVPN routes.
        """
        output = self.run_show_command(node, 'bgp evpn')
        count = 0
        for line in output.split('\n'):
            if line.strip().startswith('* >'):
                count += 1
        return count

    def get_evpn_type2_count(self, node):
        """Count EVPN Type 2 (MAC/IP) routes on a node.

        Returns:
            Integer count of Type 2 routes.
        """
        output = self.run_show_command(node, 'bgp evpn route-type mac-ip')
        count = 0
        for line in output.split('\n'):
            if line.strip().startswith('* >'):
                count += 1
        return count

    def get_evpn_type3_count(self, node):
        """Count EVPN Type 3 (IMET) routes on a node.

        Returns:
            Integer count of Type 3 routes.
        """
        output = self.run_show_command(node, 'bgp evpn route-type imet')
        count = 0
        for line in output.split('\n'):
            if line.strip().startswith('* >'):
                count += 1
        return count

    def get_vxlan_vtep_count(self, node):
        """Count remote VTEPs known to a leaf node.

        Returns:
            Integer count of remote VTEPs.
        """
        output = self.run_show_command(node, 'vxlan vtep')
        count = 0
        for line in output.split('\n'):
            if line.strip() and not line.startswith('Remote') and not line.startswith('VTEP') and not line.startswith('---') and not line.startswith('Total') and line.strip():
                # Parse VTEP IP lines
                parts = line.strip().split()
                if len(parts) >= 1 and '.' in parts[0]:
                    count += 1
        return count

    def get_vxlan_mac_count(self, node):
        """Count remote MAC addresses learned via EVPN on a leaf node.

        Returns:
            Integer count of remote EVPN MAC entries.
        """
        output = self.run_show_command(node, 'vxlan address-table')
        count = 0
        for line in output.split('\n'):
            if 'EVPN' in line:
                count += 1
        return count

    def check_vxlan_interface_up(self, node):
        """Check if VxLAN1 interface is up on a leaf node.

        Returns:
            Boolean True if Vxlan1 is up.
        """
        output = self.run_show_command(node, 'interfaces vxlan 1')
        return 'Vxlan1 is up' in output

    def check_vxlan_source_interface(self, node, expected_ip):
        """Check if VxLAN1 source-interface is active with expected IP.

        Returns:
            Boolean True if source-interface matches expected IP.
        """
        output = self.run_show_command(node, 'interfaces vxlan 1')
        return f'active with {expected_ip}' in output

    def check_vxlan_vni_mapping(self, node, vlan, vni):
        """Check if VLAN-to-VNI mapping exists on VxLAN1.

        Returns:
            Boolean True if mapping [vlan, vni] exists.
        """
        output = self.run_show_command(node, 'interfaces vxlan 1')
        return f'[{vlan}, {vni}]' in output

    def check_vxlan_flood_mode(self, node, expected_mode='headend'):
        """Check if VxLAN flood mode matches expected.

        Returns:
            Boolean True if flood mode matches.
        """
        output = self.run_show_command(node, 'interfaces vxlan 1')
        return expected_mode in output.lower()

    def check_evpn_neighbor_established(self, node, neighbor_ip):
        """Check if a specific EVPN BGP neighbor is Established.

        Returns:
            Boolean True if neighbor is Established.
        """
        output = self.run_show_command(node, 'bgp evpn summary')
        return neighbor_ip in output and 'Estab' in output
