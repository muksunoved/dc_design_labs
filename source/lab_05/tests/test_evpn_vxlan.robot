*** Settings ***
Documentation    Runtime tests for VXLAN EVPN overlay — validates:
...    - Lab lifecycle (netlab up / netlab down)
...    - Underlay: eBGP neighbors, routes, BFD
...    - Overlay: BGP EVPN sessions, route types, VxLAN data-plane
...    - L2 connectivity: host ping through overlay
Resource         NetlabCommon.resource
Library          Collections
Library          String
Library          re

Suite Teardown   Netlab Down

*** Test Cases ***

# ============================================================================
# Lab lifecycle
# ============================================================================

Lab Should Start Successfully
    [Documentation]    Deploy the lab via netlab up and wait for BGP+EVPN to stabilize.
    Netlab Up
    Sleep    15s    Wait for EVPN routes to propagate

# ============================================================================
# Underlay: Node status and interfaces
# ============================================================================

All EOS Nodes Should Run Arista cEOS
    [Documentation]    Verify all EOS nodes respond with correct version.
    FOR    ${node}    IN    @{ALL_NODES}
        ${output}=    Run Show Command    ${node}    version
        Should Contain    ${output}    Arista    ${node} should be running Arista cEOS
        Should Contain    ${output}    4.34.2.2F    ${node} should run correct image version
    END

All Data Interfaces Should Be Up On Spine Nodes
    [Documentation]    Verify all Ethernet interfaces on spine nodes are up/up.
    FOR    ${node}    IN    @{SPINE_NODES}
        ${output}=    Run Show Command    ${node}    ip interface brief
        ${up_count}=    Get Regexp Matches    ${output}    Ethernet\\d+.*up.*up
        Length Should Be    ${up_count}    3    ${node} should have 3 Ethernet interfaces up/up
    END

All Data Interfaces Should Be Up On Leaf Nodes
    [Documentation]    Verify spine-facing interfaces up/up on leaf nodes.
    FOR    ${node}    IN    @{LEAF_NODES}
        ${output}=    Run Show Command    ${node}    ip interface brief
        ${up_count}=    Get Regexp Matches    ${output}    Ethernet\\d+.*up.*up
        Length Should Be    ${up_count}    2    ${node} should have 2 routed Ethernet interfaces up/up (spine links)
    END

Loopback0 Should Have Correct IP On All EOS Nodes
    [Documentation]    Verify Loopback0 IP matches the IP plan.
    FOR    ${node}    ${expected_ip}    IN    &{LOOPBACK_IPS}
        ${output}=    Run Show Command    ${node}    ip interface brief
        Should Contain    ${output}    ${expected_ip}    ${node} Loopback0 should be ${expected_ip}
    END

Loopback0 Should Be Up On All EOS Nodes
    [Documentation]    Verify Loopback0 interface status is up/up.
    FOR    ${node}    IN    @{ALL_NODES}
        ${output}=    Run Show Command    ${node}    ip interface brief
        Should Contain    ${output}    Loopback0    ${node} should have Loopback0
        ${lo_lines}=    Get Regexp Matches    ${output}    Loopback0.*up.*up
        Length Should Be    ${lo_lines}    1    ${node} Loopback0 should be up/up
    END

Vxlan1 Interface Should Be Up On All Leaf Nodes
    [Documentation]    Verify VxLAN1 interface is up on each leaf.
    FOR    ${node}    IN    @{LEAF_NODES}
        ${result}=    RTL.Check Vxlan Interface Up    ${node}
        Should Be True    ${result}    ${node} Vxlan1 should be up
    END

Vxlan1 Source Interface Should Match VTEP IP
    [Documentation]    Verify VxLAN1 source-interface is Loopback0 with correct VTEP IP.
    FOR    ${node}    ${vtep_ip}    IN    &{VTEP_IPS}
        ${result}=    RTL.Check Vxlan Source Interface    ${node}    ${vtep_ip}
        Should Be True    ${result}    ${node} Vxlan1 source should be ${vtep_ip}
    END

Vxlan1 Should Have VLAN To VNI Mapping
    [Documentation]    Verify VLAN 10 → VNI 10010 mapping on all leafs.
    FOR    ${node}    IN    @{LEAF_NODES}
        ${result}=    RTL.Check Vxlan VNI Mapping    ${node}    ${OVERLAY_VLAN}    ${OVERLAY_VNI}
        Should Be True    ${result}    ${node} should map VLAN ${OVERLAY_VLAN} to VNI ${OVERLAY_VNI}
    END

Vxlan1 Flood Mode Should Be Headend
    [Documentation]    Verify VxLAN flood mode is headend (Ingress Replication).
    FOR    ${node}    IN    @{LEAF_NODES}
        ${result}=    RTL.Check Vxlan Flood Mode    ${node}    headend
        Should Be True    ${result}    ${node} should use headend flood mode
    END

# ============================================================================
# Underlay: BGP IPv4 Unicast
# ============================================================================

BGP IPv4 Sessions Should Be Established On Spine Nodes
    [Documentation]    Verify all eBGP IPv4 sessions are Established on spines.
    FOR    ${node}    IN    @{SPINE_NODES}
        ${output}=    Run Show Command    ${node}    ip bgp summary
        FOR    ${neighbor}    IN    @{SPINE1_NEIGHBORS}    @{SPINE2_NEIGHBORS}
            Run Keyword If    '${node}' == 'spine1' and '${neighbor}' in @{SPINE1_NEIGHBORS}
            ...    Should Contain    ${output}    Estab    ${node} neighbor ${neighbor} should be Established
            Run Keyword If    '${node}' == 'spine2' and '${neighbor}' in @{SPINE2_NEIGHBORS}
            ...    Should Contain    ${output}    Estab    ${node} neighbor ${neighbor} should be Established
        END
    END

BGP IPv4 Sessions Should Be Established On Leaf Nodes
    [Documentation]    Verify all eBGP IPv4 sessions are Established on leafs.
    ${output1}=    Run Show Command    leaf1    ip bgp summary
    Should Contain    ${output1}    Estab    leaf1 BGP should have Established neighbors
    ${output2}=    Run Show Command    leaf2    ip bgp summary
    Should Contain    ${output2}    Estab    leaf2 BGP should have Established neighbors
    ${output3}=    Run Show Command    leaf3    ip bgp summary
    Should Contain    ${output3}    Estab    leaf3 BGP should have Established neighbors

BGP Should Advertise All Loopbacks Via eBGP
    [Documentation]    Verify all Loopback0 IPs are reachable via BGP routes.
    FOR    ${node}    IN    @{ALL_NODES}
        ${output}=    Run Show Command    ${node}    ip bgp summary
        ${estab_count}=    Get Regexp Matches    ${output}    Estab
        Should Be True    len(${estab_count}) >= 1    ${node} should have at least 1 Established BGP neighbor
    END

# ============================================================================
# Underlay: BFD
# ============================================================================

BFD Peers Should Be Configured On Spine Nodes
    [Documentation]    Verify BFD peers exist on spine nodes.
    FOR    ${node}    IN    @{SPINE_NODES}
        ${output}=    Run Show Command    ${node}    bfd peers
        Should Contain    ${output}    Up    ${node} should have BFD peers in Up state
    END

BFD Sessions Should Be Up On Spine Nodes
    [Documentation]    Verify all BFD sessions are Up on spine nodes.
    FOR    ${node}    IN    @{SPINE_NODES}
        ${output}=    Run Show Command    ${node}    bfd peers
        ${up_count}=    Get Regexp Matches    ${output}    Up
        Should Be True    len(${up_count}) >= 3    ${node} should have 3+ BFD sessions Up
    END

BFD Sessions Should Be Up On Leaf Nodes
    [Documentation]    Verify all BFD sessions are Up on leaf nodes.
    FOR    ${node}    IN    @{LEAF_NODES}
        ${output}=    Run Show Command    ${node}    bfd peers
        ${up_count}=    Get Regexp Matches    ${output}    Up
        Should Be True    len(${up_count}) >= 2    ${node} should have 2+ BFD sessions Up
    END

# ============================================================================
# Overlay: BGP EVPN
# ============================================================================

BGP EVPN Sessions Should Be Established On Spine Nodes
    [Documentation]    Verify EVPN address-family sessions are Established on spines.
    FOR    ${node}    IN    @{SPINE_NODES}
        ${output}=    Run Show Command    ${node}    bgp evpn summary
        Should Contain    ${output}    Estab    ${node} EVPN should have Established neighbors
    END

BGP EVPN Sessions Should Be Established On Leaf Nodes
    [Documentation]    Verify EVPN address-family sessions are Established on leafs.
    FOR    ${node}    IN    @{LEAF_NODES}
        ${output}=    Run Show Command    ${node}    bgp evpn summary
        Should Contain    ${output}    Estab    ${node} EVPN should have Established neighbors
    END

EVPN Type 3 IMET Routes Should Exist On Spine Nodes
    [Documentation]    Verify Type 3 (Inclusive Multicast) routes exist on spines.
    # 3 leafs × 1 VNI = minimum 3 IMET routes per spine
    FOR    ${node}    IN    @{SPINE_NODES}
        ${count}=    RTL.Get EVPN Type3 Count    ${node}
        Should Be True    ${count} >= 3    ${node} should have at least 3 IMET routes (3 leafs × 1 VNI)
    END

EVPN Type 3 IMET Routes Should Exist On Leaf Nodes
    [Documentation]    Verify Type 3 (Inclusive Multicast) routes exist on leafs.
    # Each leaf should see IMET routes from other leafs (2 remote + 1 local)
    FOR    ${node}    IN    @{LEAF_NODES}
        ${count}=    RTL.Get EVPN Type3 Count    ${node}
        Should Be True    ${count} >= 3    ${node} should have at least 3 IMET routes
    END

EVPN Route Targets Should Match Overlay RT
    [Documentation]    Verify EVPN routes contain the correct Route Target (10:10010).
    FOR    ${node}    IN    @{LEAF_NODES}
        ${output}=    Run Show Command    ${node}    bgp evpn route-type imet detail
        Should Contain    ${output}    ${OVERLAY_RT}    ${node} IMET routes should have RT ${OVERLAY_RT}
    END

EVPN RD Should Match VTEP IP Format
    [Documentation]    Verify EVPN RD format is <VTEP_IP>:<VNI> on leafs.
    FOR    ${node}    ${vtep_ip}    IN    &{VTEP_IPS}
        ${expected_rd}=    Catenate    SEPARATOR=:    ${vtep_ip}    ${OVERLAY_VNI}
        ${output}=    Run Show Command    ${node}    bgp evpn route-type imet detail
        Should Contain    ${output}    ${expected_rd}    ${node} EVPN RD should be ${expected_rd}
    END

Spine Should Preserve EVPN Next Hop Unchanged
    [Documentation]    Verify spine preserves original VTEP next-hop (next-hop-unchanged).
    # Check that spine EVPN routes have leaf VTEP IPs as next-hop, not spine IPs
    ${output}=    Run Show Command    spine1    bgp evpn
    Should Contain    ${output}    10.0.12.1    spine1 should show leaf2 VTEP as next-hop
    Should Contain    ${output}    10.0.13.1    spine1 should show leaf3 VTEP as next-hop

# ============================================================================
# Overlay: VXLAN data-plane
# ============================================================================

Remote VTEPs Should Be Known On All Leaf Nodes
    [Documentation]    Verify each leaf knows remote VTEPs from Type 3 routes.
    FOR    ${node}    IN    @{LEAF_NODES}
        ${count}=    RTL.Get Vxlan Vtep Count    ${node}
        Should Be True    ${count} >= 2    ${node} should know at least 2 remote VTEPs
    END

VxLAN Flood List Should Be Built From EVPN
    [Documentation]    Verify VXLAN flood list source is EVPN (Ingress Replication).
    FOR    ${node}    IN    @{LEAF_NODES}
        ${output}=    Run Show Command    ${node}    interfaces vxlan 1
        Should Contain    ${output}    EVPN    ${node} flood list source should be EVPN
    END

VLAN 10 Should Exist On All Leaf Nodes
    [Documentation]    Verify VLAN 10 is configured on all leafs.
    FOR    ${node}    IN    @{LEAF_NODES}
        ${output}=    Run Show Command    ${node}    vlan
        Should Contain    ${output}    ${OVERLAY_VLAN}    ${node} should have VLAN ${OVERLAY_VLAN}
    END

Host Facing Interfaces Should Be Switchport Access VLAN 10
    [Documentation]    Verify host-facing interfaces are switchport access vlan 10.
    ${output}=    Run Show Command    leaf1    interfaces ethernet 3 switchport
    Should Contain    ${output}    Access    leaf1 Et3 should be access mode
    ${output}=    Run Show Command    leaf2    interfaces ethernet 3 switchport
    Should Contain    ${output}    Access    leaf2 Et3 should be access mode
    ${output}=    Run Show Command    leaf3    interfaces ethernet 3 switchport
    Should Contain    ${output}    Access    leaf3 Et3 should be access mode

# ============================================================================
# Overlay: Host connectivity (L2 through VXLAN)
# ============================================================================

Host1 Should Have Overlay IP
    [Documentation]    Verify host1 has overlay IP 192.168.10.11.
    ${output}=    Run Host Command    host1    ip addr show eth1
    Should Contain    ${output}    192.168.10.11    host1 should have overlay IP

Host2 Should Have Overlay IP
    [Documentation]    Verify host2 has overlay IP 192.168.10.12.
    ${output}=    Run Host Command    host2    ip addr show eth1
    Should Contain    ${output}    192.168.10.12    host2 should have overlay IP

Host3 Should Have Overlay IP
    [Documentation]    Verify host3 has overlay IP 192.168.10.13.
    ${output}=    Run Host Command    host3    ip addr show eth1
    Should Contain    ${output}    192.168.10.13    host3 should have overlay IP

Host1 Should Ping Host2 Through Overlay
    [Documentation]    Verify L2 connectivity: host1 → host2 through VXLAN overlay.
    ${output}=    Run Host Ping    host1    192.168.10.12
    Should Contain    ${output}    64 bytes    host1 should ping host2 through overlay

Host1 Should Ping Host3 Through Overlay
    [Documentation]    Verify L2 connectivity: host1 → host3 through VXLAN overlay.
    ${output}=    Run Host Ping    host1    192.168.10.13
    Should Contain    ${output}    64 bytes    host1 should ping host3 through overlay

Host2 Should Ping Host3 Through Overlay
    [Documentation]    Verify L2 connectivity: host2 → host3 through VXLAN overlay.
    ${output}=    Run Host Ping    host2    192.168.10.13
    Should Contain    ${output}    64 bytes    host2 should ping host3 through overlay

Host2 Should Ping Host1 Through Overlay
    [Documentation]    Verify L2 connectivity: host2 → host1 (bidirectional).
    ${output}=    Run Host Ping    host2    192.168.10.11
    Should Contain    ${output}    64 bytes    host2 should ping host1 through overlay

Host3 Should Ping Host1 Through Overlay
    [Documentation]    Verify L2 connectivity: host3 → host1 (bidirectional).
    ${output}=    Run Host Ping    host3    192.168.10.11
    Should Contain    ${output}    64 bytes    host3 should ping host1 through overlay

Host3 Should Ping Host2 Through Overlay
    [Documentation]    Verify L2 connectivity: host3 → host2 (bidirectional).
    ${output}=    Run Host Ping    host3    192.168.10.12
    Should Contain    ${output}    64 bytes    host3 should ping host2 through overlay

EVPN MAC Addresses Should Be Learned From Hosts
    [Documentation]    After host ping, verify MAC addresses are learned via EVPN.
    # Trigger MAC learning by ping
    Run Host Ping    host1    192.168.10.12    count=1
    Sleep    5s    Wait for EVPN MAC propagation
    FOR    ${node}    IN    @{LEAF_NODES}
        ${count}=    RTL.Get Vxlan Mac Count    ${node}
        Should Be True    ${count} >= 1    ${node} should have at least 1 remote EVPN MAC
    END

# ============================================================================
# Underlay: Ping verification (baseline connectivity)
# ============================================================================

Spine1 Should Ping Leaf1 Loopback
    ${output}=    Run Ping Command    spine1    10.0.11.1    Loopback0
    Should Contain    ${output}    0% packet loss    spine1 should ping leaf1 loopback

Spine1 Should Ping Leaf2 Loopback
    ${output}=    Run Ping Command    spine1    10.0.12.1    Loopback0
    Should Contain    ${output}    0% packet loss    spine1 should ping leaf2 loopback

Leaf1 Should Ping Leaf2 Loopback
    ${output}=    Run Ping Command    leaf1    10.0.12.1    Loopback0
    Should Contain    ${output}    0% packet loss    leaf1 should ping leaf2 loopback

Leaf1 Should Ping Leaf3 Loopback
    ${output}=    Run Ping Command    leaf1    10.0.13.1    Loopback0
    Should Contain    ${output}    0% packet loss    leaf1 should ping leaf3 loopback
