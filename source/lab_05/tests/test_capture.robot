*** Settings ***
Documentation    Packet capture tests — passive (no interface disruption).
...    Captures BFD, LLDP, BGP keepalives on the underlay, and
...    VXLAN traffic triggered by host ping.
...    Lab lifecycle is managed via `netlab up` / `netlab down`.
Resource         NetlabCommon.resource
Library          Collections
Library          String
Library          Process
Library          re

Suite Setup      Run Keywords
...              Check Rootless Prerequisites    AND
...              Load IP Plan Variables    AND
...              Netlab Up
Suite Teardown   Netlab Down

*** Variables ***
${UNDERLAY_IFACE}      et1
${HOST_IFACE}          et3
${VXLAN_FILTER}        udp port 4789
${BFD_FILTER}          udp port 3784
${BGP_FILTER}          tcp port 179
${LLDP_FILTER}         ether proto 0x88cc
${ARP_FILTER}          arp
${ICMP_FILTER}         icmp

*** Test Cases ***

# ============================================================================
# BFD — Underlay (periodic, no trigger needed)
# ============================================================================

BFD Packets Should Be Captured On Leaf1 Underlay
    [Documentation]    Capture BFD control packets on leaf1 underlay link.
    ${output}=    Capture Packets    leaf1    ${UNDERLAY_IFACE}    ${BFD_FILTER}    5    10
    Should Not Be Empty    ${output}    Should have captured BFD packets
    ${count}=    Count Matches    ${output}    BFD
    Should Be True    ${count} >= 5    Should capture at least 5 BFD packets

BFD Packets Should Have State Up
    [Documentation]    Verify BFD packets have State Up.
    ${output}=    Capture Packets Verbose    leaf1    ${UNDERLAY_IFACE}    ${BFD_FILTER}    3    10
    Should Contain    ${output}    State Up    BFD packets should have State Up

BFD Packets Should Have Correct Timers
    [Documentation]    Verify BFD interval is 100ms.
    ${output}=    Capture Packets Verbose    leaf1    ${UNDERLAY_IFACE}    ${BFD_FILTER}    2    10
    Should Contain    ${output}    Desired min Tx Interval:     100 ms
    Should Contain    ${output}    Required min Rx Interval:    100 ms

BFD Packets Should Have Multiplier 3
    [Documentation]    Verify BFD multiplier is 3.
    ${output}=    Capture Packets Verbose    leaf1    ${UNDERLAY_IFACE}    ${BFD_FILTER}    2    10
    Should Contain    ${output}    Multiplier: 3

BFD Packets Should Have TTL 255
    [Documentation]    Verify BFD packets have TTL 255 (security).
    ${output}=    Capture Packets Verbose    leaf1    ${UNDERLAY_IFACE}    ${BFD_FILTER}    2    10
    Should Contain    ${output}    ttl 255    BFD packets should have TTL 255

BFD Packets Should Be Captured On Spine1 Underlay
    [Documentation]    Capture BFD on spine1 underlay link.
    ${output}=    Capture Packets    spine1    et1    ${BFD_FILTER}    5    10
    Should Not Be Empty    ${output}    Should have captured BFD packets on spine1
    ${count}=    Count Matches    ${output}    BFD
    Should Be True    ${count} >= 5    Should capture at least 5 BFD packets on spine1

# ============================================================================
# LLDP — Underlay (periodic ~30s, needs longer timeout)
# ============================================================================

LLDP Packets Should Be Captured On Leaf1 Underlay
    [Documentation]    Capture LLDP frames on leaf1 underlay link.
    ${output}=    Capture Packets    leaf1    ${UNDERLAY_IFACE}    ${LLDP_FILTER}    2    60
    Should Not Be Empty    ${output}    Should have captured LLDP frames
    Should Contain    ${output}    LLDP    Should see LLDP in output

LLDP Should Contain Leaf1 Port ID
    [Documentation]    Verify LLDP frame contains leaf1 port information.
    ${output}=    Capture Packets Verbose    leaf1    ${UNDERLAY_IFACE}    ${LLDP_FILTER}    2    60
    Should Not Be Empty    ${output}    Should have captured verbose LLDP

# ============================================================================
# BGP Keepalives — Underlay (periodic ~60s, needs longer timeout)
# ============================================================================

BGP Keepalive Packets Should Be Captured On Leaf1 Underlay
    [Documentation]    Capture BGP keepalive packets on leaf1 underlay.
    ${output}=    Capture Packets    leaf1    ${UNDERLAY_IFACE}    ${BGP_FILTER}    2    90
    Should Not Be Empty    ${output}    Should have captured BGP packets

# ============================================================================
# VXLAN — triggered by background host ping
# ============================================================================

VXLAN Packets Should Be Captured On Leaf1 Underlay
    [Documentation]    Capture VXLAN packets while host1 pings host2.
    ...    Uses 'any' interface to capture across all paths (ECMP).
    ${ping}=    Start Process    docker    exec    clab-netlab-host1
    ...    ping    -c    30    -i    0.3    ${HOST_OVERLAY_IPS}[host2]
    Sleep    2s    Let ping start and ARP resolve
    ${output}=    Capture Packets    leaf1    any    ${VXLAN_FILTER}    5    40
    Wait For Process    ${ping}    timeout=45
    Should Not Be Empty    ${output}    Should have captured VXLAN packets

VXLAN Packets Should Use UDP Port 4789
    [Documentation]    Verify VXLAN packets use UDP port 4789.
    ${ping}=    Start Process    docker    exec    clab-netlab-host1
    ...    ping    -c    30    -i    0.3    ${HOST_OVERLAY_IPS}[host2]
    Sleep    2s    Let ping start and ARP resolve
    ${output}=    Capture Packets Verbose    leaf1    any    ${VXLAN_FILTER}    3    40
    Wait For Process    ${ping}    timeout=45
    Should Not Be Empty    ${output}    Should have captured VXLAN verbose output
    Should Contain    ${output}    4789    VXLAN packets should use UDP port 4789

VXLAN Packets Should Have Correct Outer IPs
    [Documentation]    Verify VXLAN outer IP src/dst (VTEP-to-VTEP).
    ${ping}=    Start Process    docker    exec    clab-netlab-host1
    ...    ping    -c    30    -i    0.3    ${HOST_OVERLAY_IPS}[host2]
    Sleep    2s    Let ping start and ARP resolve
    ${output}=    Capture Packets    leaf1    any    ${VXLAN_FILTER}    3    40
    Wait For Process    ${ping}    timeout=45
    Should Contain    ${output}    ${VTEP_IPS}[leaf1]    VXLAN outer src should be leaf1 VTEP
    Should Contain    ${output}    ${VTEP_IPS}[leaf2]    VXLAN outer dst should be leaf2 VTEP

VXLAN Return Traffic Should Be Captured On Leaf2
    [Documentation]    Verify VXLAN return traffic (leaf2 → leaf1) during host ping.
    ${ping}=    Start Process    docker    exec    clab-netlab-host1
    ...    ping    -c    30    -i    0.3    ${HOST_OVERLAY_IPS}[host2]
    Sleep    2s    Let ping start and ARP resolve
    ${output}=    Capture Packets    leaf2    any    ${VXLAN_FILTER}    3    40
    Wait For Process    ${ping}    timeout=45
    Should Contain    ${output}    ${VTEP_IPS}[leaf2]    Return VXLAN src should be leaf2 VTEP
    Should Contain    ${output}    ${VTEP_IPS}[leaf1]    Return VXLAN dst should be leaf1 VTEP
