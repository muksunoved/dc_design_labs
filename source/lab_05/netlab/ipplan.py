"""
Netlab plugin: ipplan

Reads IP addresses from ip-plan.yml and populates:
- topology.nodes.<name>.loopback.ipv4
- topology.links with IP addresses and graph labels
- host*.sh startup scripts with overlay IP addresses

Usage in topology.yml:
  plugin: [ipplan]
"""

import yaml
from pathlib import Path
from box import Box


HOST_SH_TEMPLATE = """\
#!/bin/bash
# {host_comment} startup configuration — applied by netlab files plugin
# eth1 connects to {leaf_name} (VLAN {vlan_id} access port — VXLAN overlay)
# Overlay: VLAN {vlan_id} / VNI {vni} / subnet {subnet}

# Install networking tools (not present in minimal Ubuntu 22.04 image)
apt-get update -qq > /dev/null 2>&1
apt-get install -y -qq iproute2 iputils-ping > /dev/null 2>&1

# Wait for interface to be available
sleep 2

# Assign overlay IP on eth1 (VLAN {vlan_id} subnet)
ip addr add {overlay_ip} dev eth1 2>/dev/null || true
ip link set eth1 up

# Loop to keep container alive
while true; do sleep 60; done
"""


def topology_expand(topology: Box) -> None:
    """
    Read ip-plan.yml and populate topology before links_init() runs.
    This hook is called BEFORE augment.links.links_init(), so our links
    will be normalized and validated correctly.
    """
    ip_plan_path = Path('ip-plan.yml')
    if not ip_plan_path.exists():
        print("WARNING: ipplan plugin: ip-plan.yml not found, skipping")
        return

    with open(ip_plan_path) as f:
        ip_plan = yaml.safe_load(f)

    # Set loopback addresses for each node
    for node_name, node_data in ip_plan.items():
        if node_name not in topology.nodes:
            continue
        if 'loopback' in node_data:
            if 'loopback' not in topology.nodes[node_name]:
                topology.nodes[node_name].loopback = Box({})
            topology.nodes[node_name].loopback.ipv4 = node_data['loopback']

    # Build links list from ip-plan
    links = []
    host_to_leaf = {}
    for node_name, node_data in ip_plan.items():
        if 'links' not in node_data:
            continue
        for peer_name, link_data in node_data['links'].items():
            local_ip = link_data['local']
            remote_ip = link_data['remote']
            subnet_label = local_ip  # Use local IP as subnet label

            link_entry = Box({
                node_name: Box({'ipv4': local_ip}),
                peer_name: Box({'ipv4': remote_ip}),
                'graph': Box({'format': {'label': subnet_label}})
            })
            links.append(link_entry)

            if node_name.startswith('leaf') and peer_name.startswith('host'):
                host_to_leaf[peer_name] = node_name

    topology.links = links

    # Process overlay section — generate host*.sh startup scripts
    overlay = ip_plan.get('overlay')
    if not overlay:
        return

    overlay_hosts = overlay.get('hosts', {})
    vlans = overlay.get('vlans', {})

    # Use the first VLAN entry for overlay metadata
    vlan_id = None
    vni = None
    subnet = None
    for vid, vlan_data in vlans.items():
        vlan_id = vid
        vni = vlan_data.get('vni', '')
        subnet = vlan_data.get('subnet', '')
        break

    for host_name, overlay_ip in overlay_hosts.items():
        leaf_name = host_to_leaf.get(host_name, 'leaf')
        host_comment = host_name.capitalize()

        content = HOST_SH_TEMPLATE.format(
            host_comment=host_comment,
            leaf_name=leaf_name,
            vlan_id=vlan_id,
            vni=vni,
            subnet=subnet,
            overlay_ip=overlay_ip,
        )

        sh_path = Path(f'{host_name}.sh')
        sh_path.write_text(content)
        print(f"ipplan plugin: generated {sh_path} with overlay IP {overlay_ip}")
