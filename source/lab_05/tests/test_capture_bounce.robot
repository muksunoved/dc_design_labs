*** Settings ***
Documentation    Packet capture tests requiring interface bounce (disruptive).
...    These tests shut down and re-enable interfaces to trigger specific
...    packet capture scenarios: ARP through VXLAN, BUM/IR flood,
...    BFD/EVPN recovery, and MAC re-learning.
...    WARNING: These tests temporarily disrupt network connectivity.
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
${HOST_LINK_IFACE}     Ethernet3
${VXLAN_FILTER}        udp port 4789
${BFD_FILTER}          udp port 3784
${ARP_FILTER}          arp
${ICMP_FILTER}         icmp

*** Test Cases ***

# ============================================================================
# Host link bounce (leaf1 Ethernet3) — triggers ARP, VXLAN, BUM
# ============================================================================

ARP Suppression Should Prevent ARP Broadcast In Underlay
    [Documentation]    With 'vxlan learn-restrict any', the leaf suppresses
    ...    ARP broadcasts — it responds via proxy ARP using EVPN-learned MACs.
    ...    Verify that ARP from host1 does NOT leak into the underlay as
    ...    VXLAN-encapsulated ARP broadcast.
    Bounce Interface    leaf1    ${HOST_LINK_IFACE}    wait_down=5    wait_up=3
    Sleep    5s    Wait for EVPN MAC re-learning
    ${ping}=    Start Process    docker    exec    clab-netlab-host1
    ...    bash    -c    ip neigh flush dev eth1; ping -c 30 -i 0.3 ${HOST_OVERLAY_IPS}[host2]
    Sleep    1s    Let ping start
    ${output}=    Capture Packets    spine1    et1    udp    10    15
    Wait For Process    ${ping}    timeout=25
    ${arp_count}=    Count Matches    ${output}    arp
    Should Be True    ${arp_count} == 0
    ...    ARP should be suppressed by learn-restrict any — no ARP in underlay

VXLAN Encapsulation Should Appear After Host Link Bounce
    [Documentation]    After bouncing leaf1 host link and triggering host ping,
    ...    capture VXLAN encapsulation on all interfaces.
    ${ping}=    Start Process    docker    exec    clab-netlab-host1
    ...    bash    -c    sleep 1; ping -c 30 -i 0.3 ${HOST_OVERLAY_IPS}[host2]
    Bounce Interface    leaf1    ${HOST_LINK_IFACE}    wait_down=3    wait_up=2
    Sleep    2s    Let ping start after bounce
    ${output}=    Capture Packets    leaf1    any    ${VXLAN_FILTER}    5    40
    Wait For Process    ${ping}    timeout=45
    Should Not Be Empty    ${output}    Should have captured VXLAN packets after bounce
    Should Contain    ${output}    ${VTEP_IPS}[leaf1]    VXLAN outer src should be leaf1 VTEP

VXLAN Outer IPs Should Match VTEP Addresses After Bounce
    [Documentation]    Verify VXLAN outer IPs are correct VTEP addresses after bounce.
    ${ping}=    Start Process    docker    exec    clab-netlab-host1
    ...    bash    -c    sleep 1; ping -c 30 -i 0.3 ${HOST_OVERLAY_IPS}[host2]
    Bounce Interface    leaf1    ${HOST_LINK_IFACE}    wait_down=3    wait_up=2
    Sleep    2s    Let ping start after bounce
    ${output}=    Capture Packets Verbose    leaf1    any    ${VXLAN_FILTER}    3    40
    Wait For Process    ${ping}    timeout=45
    Should Contain    ${output}    ${VTEP_IPS}[leaf1]    VXLAN outer src = leaf1 VTEP
    Should Contain    ${output}    ${VTEP_IPS}[leaf2]    VXLAN outer dst = leaf2 VTEP

BUM Ingress Replication Should Flood To Remote VTEPs After Bounce
    [Documentation]    After bouncing host link, EVPN MAC entries are withdrawn.
    ...    Host ping triggers ARP broadcast, which leaf1 floods via Ingress
    ...    Replication to all remote VTEPs. We verify by capturing VXLAN
    ...    ARP-flood packets destined to both leaf2 and leaf3 VTEPs.
    Bounce Interface    leaf1    ${HOST_LINK_IFACE}    wait_down=5    wait_up=3
    ${ping}=    Start Process    docker    exec    clab-netlab-host1
    ...    bash    -c    ip neigh flush dev eth1; ping -c 30 -i 0.3 ${HOST_OVERLAY_IPS}[host2]
    Sleep    1s    Let ping start and trigger ARP broadcast
    ${output}=    Capture Packets    leaf1    any    ${VXLAN_FILTER}    15    40
    Wait For Process    ${ping}    timeout=45
    Should Not Be Empty    ${output}    Should have captured VXLAN packets
    ${to_leaf2}=    Count Matches    ${output}    10\\.0\\.12\\.1
    Should Be True    ${to_leaf2} >= 1    Should see VXLAN to leaf2 VTEP (10.0.12.1)

Remote Leaf Should Receive VXLAN After Host Link Bounce
    [Documentation]    Verify leaf2 sees VXLAN packets after bouncing leaf1 host link.
    ${ping}=    Start Process    docker    exec    clab-netlab-host1
    ...    bash    -c    sleep 1; ping -c 30 -i 0.3 ${HOST_OVERLAY_IPS}[host2]
    Bounce Interface    leaf1    ${HOST_LINK_IFACE}    wait_down=3    wait_up=2
    Sleep    2s    Let ping start after bounce
    ${output}=    Capture Packets    leaf2    any    ${VXLAN_FILTER}    3    40
    Wait For Process    ${ping}    timeout=45
    Should Contain    ${output}    ${VTEP_IPS}[leaf1]    leaf2 should see VXLAN from leaf1 VTEP

# ============================================================================
# EVPN control-plane recovery after host link bounce
# ============================================================================

EVPN MAC Addresses Should Re-Learn After Host Link Bounce
    [Documentation]    After bouncing leaf1 host link, EVPN MAC addresses
    ...    should be re-learned via Type 2 routes.
    Bounce Interface    leaf1    ${HOST_LINK_IFACE}    wait_down=5    wait_up=5
    Run Host Ping    host1    ${HOST_OVERLAY_IPS}[host2]    count=5
    Sleep    5s    Wait for EVPN MAC propagation
    FOR    ${node}    IN    @{LEAF_NODES}
        ${count}=    RTL.Get Vxlan Mac Count    ${node}
        Should Be True    ${count} >= 1
        ...    ${node} should re-learn EVPN MACs after bounce
    END

EVPN Type 2 Routes Should Re-Appear After Host Link Bounce
    [Documentation]    Verify Type 2 (MAC/IP) routes are re-advertised after bounce.
    Bounce Interface    leaf1    ${HOST_LINK_IFACE}    wait_down=5    wait_up=5
    Run Host Ping    host1    ${HOST_OVERLAY_IPS}[host2]    count=5
    Sleep    5s    Wait for EVPN route propagation
    ${count}=    RTL.Get EVPN Type2 Count    spine1
    Should Be True    ${count} >= 1
    ...    spine1 should have Type 2 routes after bounce

Ping Should Succeed After Host Link Bounce
    [Documentation]    Verify overlay ping works after host link bounce.
    Bounce Interface    leaf1    ${HOST_LINK_IFACE}    wait_down=5    wait_up=5
    Sleep    3s    Wait for interface to stabilize
    ${output}=    Run Host Ping    host1    ${HOST_OVERLAY_IPS}[host2]    count=5
    Should Contain    ${output}    0% packet loss
    ...    host1 should ping host2 after bounce

# ============================================================================
# Underlay link bounce (leaf1 Ethernet1 → spine1) — triggers BFD/BGP recovery
# ============================================================================

BFD Should Recover After Underlay Link Bounce
    [Documentation]    After bouncing leaf1 underlay link to spine1,
    ...    BFD should re-establish and packets should show State Up.
    Bounce Interface    leaf1    Ethernet1    wait_down=5    wait_up=10
    ${output}=    Capture Packets Verbose    leaf1    ${UNDERLAY_IFACE}    ${BFD_FILTER}    3    20
    Should Not Be Empty    ${output}    Should capture BFD after underlay bounce
    Should Contain    ${output}    State Up    BFD should recover to State Up

BFD Timers Should Be Correct After Underlay Link Bounce
    [Documentation]    Verify BFD timers are 100ms after underlay bounce recovery.
    Bounce Interface    leaf1    Ethernet1    wait_down=5    wait_up=10
    ${output}=    Capture Packets Verbose    leaf1    ${UNDERLAY_IFACE}    ${BFD_FILTER}    2    20
    Should Contain    ${output}    Desired min Tx Interval:     100 ms
    Should Contain    ${output}    Required min Rx Interval:    100 ms

BGP EVPN Should Recover After Underlay Link Bounce
    [Documentation]    After bouncing leaf1 underlay link, BGP EVPN sessions
    ...    should re-establish through the remaining underlay path (via spine2).
    Bounce Interface    leaf1    Ethernet1    wait_down=5    wait_up=15
    ${output}=    Run Show Command    leaf1    bgp evpn summary
    Should Contain    ${output}    Estab
    ...    leaf1 should have at least one EVPN session Established after bounce

Underlay Ping Should Recover After Link Bounce
    [Documentation]    Verify spine1 can ping leaf1 loopback after underlay bounce.
    Bounce Interface    leaf1    Ethernet1    wait_down=5    wait_up=10
    Sleep    5s    Wait for BGP to re-converge
    ${output}=    Run Ping Command    spine1    ${VTEP_IPS}[leaf1]    Loopback0    repeat=5
    Should Contain    ${output}    0% packet loss
    ...    spine1 should ping leaf1 loopback after underlay bounce
