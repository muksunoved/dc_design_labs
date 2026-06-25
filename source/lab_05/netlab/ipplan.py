"""
Netlab plugin: ipplan

Reads IP addresses from ip-plan.yml and populates:
- topology.nodes.<name>.loopback.ipv4
- topology.links with IP addresses and graph labels

Usage in topology.yml:
  plugin: [ipplan]
"""

import yaml
from pathlib import Path
from box import Box


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

    topology.links = links
