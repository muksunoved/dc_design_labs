*** Settings ***
Documentation    Runtime tests for eBGP underlay — validates:
...    - Lab lifecycle (netlab up / netlab down)
...    - Node version and reachability
...    - Interface status (up/up)
...    - BGP neighbors (Established)
...    - BGP route exchange (all loopbacks learned)
...    - BFD configuration and sessions
...    - BGP router-id and address-family
...    - End-to-end ping (spine-to-leaf, leaf-to-leaf, leaf-to-spine, host-to-all)
Resource         NetlabCommon.resource
Library          Collections
Library          String
Library          re

Suite Teardown   Netlab Down

*** Keywords ***
Verify All EOS Nodes Respond
    [Documentation]    Verify all EOS nodes respond with correct version.
    FOR    ${node}    IN    @{ALL_NODES}
        ${output}=    Run Show Command    ${node}    version
        Should Contain    ${output}    Arista    ${node} should be running Arista cEOS
        Should Contain    ${output}    4.34.2.2F    ${node} should run correct image version
    END

*** Test Cases ***
Lab Should Start Successfully
    [Documentation]    Deploy the lab via netlab up and wait for BGP to stabilize.
    Netlab Up
    Sleep    30s    Wait for BGP sessions to establish

All EOS Nodes Should Run Arista cEOS
    Verify All EOS Nodes Respond

All Data Interfaces Should Be Up On Spine Nodes
    [Documentation]    Verify all Ethernet interfaces on spine nodes are up/up.
    FOR    ${node}    IN    spine1    spine2
        ${output}=    Run Show Command    ${node}    ip interface brief
        ${up_count}=    Get Regexp Matches    ${output}    Ethernet\\d+.*up.*up
        Length Should Be    ${up_count}    3    ${node} should have 3 Ethernet interfaces up/up
    END

All Data Interfaces Should Be Up On Leaf Nodes
    [Documentation]    Verify all Ethernet interfaces on leaf nodes are up/up.
    FOR    ${node}    IN    leaf1    leaf2    leaf3
        ${output}=    Run Show Command    ${node}    ip interface brief
        ${up_count}=    Get Regexp Matches    ${output}    Ethernet\\d+.*up.*up
        Length Should Be    ${up_count}    3    ${node} should have 3 Ethernet interfaces up/up (2 spine + 1 host)
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
        ${match}=    Get Regexp Matches    ${output}    Loopback0.*up.*up
        Length Should Be    ${match}    1    ${node} Loopback0 should be up
    END

BGP Neighbors Should Be Established On Spine1
    [Documentation]    spine1 should have 3 eBGP sessions to leaf1, leaf2, leaf3.
    ${output}=    Run Show Command    spine1    bgp neighbors
    FOR    ${neighbor_ip}    IN    @{SPINE1_NEIGHBORS}
        Should Contain    ${output}    ${neighbor_ip}    spine1 should have BGP neighbor ${neighbor_ip}
    END
    ${established_count}=    Get Regexp Matches    ${output}    (?i)BGP state is Established
    Length Should Be    ${established_count}    3    spine1 should have 3 Established BGP sessions

BGP Neighbors Should Be Established On Spine2
    [Documentation]    spine2 should have 3 eBGP sessions to leaf1, leaf2, leaf3.
    ${output}=    Run Show Command    spine2    bgp neighbors
    FOR    ${neighbor_ip}    IN    @{SPINE2_NEIGHBORS}
        Should Contain    ${output}    ${neighbor_ip}    spine2 should have BGP neighbor ${neighbor_ip}
    END
    ${established_count}=    Get Regexp Matches    ${output}    (?i)BGP state is Established
    Length Should Be    ${established_count}    3    spine2 should have 3 Established BGP sessions

BGP Neighbors Should Be Established On Leaf1
    [Documentation]    leaf1 should have 2 eBGP sessions to spine1 and spine2.
    ${output}=    Run Show Command    leaf1    bgp neighbors
    FOR    ${neighbor_ip}    IN    @{LEAF1_NEIGHBORS}
        Should Contain    ${output}    ${neighbor_ip}    leaf1 should have BGP neighbor ${neighbor_ip}
    END
    ${established_count}=    Get Regexp Matches    ${output}    (?i)BGP state is Established
    Length Should Be    ${established_count}    2    leaf1 should have 2 Established BGP sessions

BGP Neighbors Should Be Established On Leaf2
    [Documentation]    leaf2 should have 2 eBGP sessions to spine1 and spine2.
    ${output}=    Run Show Command    leaf2    bgp neighbors
    FOR    ${neighbor_ip}    IN    @{LEAF2_NEIGHBORS}
        Should Contain    ${output}    ${neighbor_ip}    leaf2 should have BGP neighbor ${neighbor_ip}
    END
    ${established_count}=    Get Regexp Matches    ${output}    (?i)BGP state is Established
    Length Should Be    ${established_count}    2    leaf2 should have 2 Established BGP sessions

BGP Neighbors Should Be Established On Leaf3
    [Documentation]    leaf3 should have 2 eBGP sessions to spine1 and spine2.
    ${output}=    Run Show Command    leaf3    bgp neighbors
    FOR    ${neighbor_ip}    IN    @{LEAF3_NEIGHBORS}
        Should Contain    ${output}    ${neighbor_ip}    leaf3 should have BGP neighbor ${neighbor_ip}
    END
    ${established_count}=    Get Regexp Matches    ${output}    (?i)BGP state is Established
    Length Should Be    ${established_count}    2    leaf3 should have 2 Established BGP sessions

BGP Should Distribute Routes On Spine1
    [Documentation]    spine1 should have BGP routes to spine2 and all leaf loopbacks.
    ${output}=    Run Show Command    spine1    ip bgp
    Should Contain    ${output}    10.0.2.1/32    spine1 should have BGP route to spine2
    Should Contain    ${output}    10.0.11.1/32    spine1 should have BGP route to leaf1
    Should Contain    ${output}    10.0.12.1/32    spine1 should have BGP route to leaf2
    Should Contain    ${output}    10.0.13.1/32    spine1 should have BGP route to leaf3

BGP Should Distribute Routes On Spine2
    [Documentation]    spine2 should have BGP routes to spine1 and all leaf loopbacks.
    ${output}=    Run Show Command    spine2    ip bgp
    Should Contain    ${output}    10.0.1.1/32    spine2 should have BGP route to spine1
    Should Contain    ${output}    10.0.11.1/32    spine2 should have BGP route to leaf1
    Should Contain    ${output}    10.0.12.1/32    spine2 should have BGP route to leaf2
    Should Contain    ${output}    10.0.13.1/32    spine2 should have BGP route to leaf3

BGP Should Distribute Routes On Leaf1
    [Documentation]    leaf1 should have BGP routes to spines and other leaves.
    ${output}=    Run Show Command    leaf1    ip bgp
    Should Contain    ${output}    10.0.1.1/32    leaf1 should have BGP route to spine1
    Should Contain    ${output}    10.0.2.1/32    leaf1 should have BGP route to spine2
    Should Contain    ${output}    10.0.12.1/32    leaf1 should have BGP route to leaf2
    Should Contain    ${output}    10.0.13.1/32    leaf1 should have BGP route to leaf3

BGP Should Distribute Routes On Leaf2
    [Documentation]    leaf2 should have BGP routes to spines and other leaves.
    ${output}=    Run Show Command    leaf2    ip bgp
    Should Contain    ${output}    10.0.1.1/32    leaf2 should have BGP route to spine1
    Should Contain    ${output}    10.0.2.1/32    leaf2 should have BGP route to spine2
    Should Contain    ${output}    10.0.11.1/32    leaf2 should have BGP route to leaf1
    Should Contain    ${output}    10.0.13.1/32    leaf2 should have BGP route to leaf3

BGP Should Distribute Routes On Leaf3
    [Documentation]    leaf3 should have BGP routes to spines and other leaves.
    ${output}=    Run Show Command    leaf3    ip bgp
    Should Contain    ${output}    10.0.1.1/32    leaf3 should have BGP route to spine1
    Should Contain    ${output}    10.0.2.1/32    leaf3 should have BGP route to spine2
    Should Contain    ${output}    10.0.11.1/32    leaf3 should have BGP route to leaf1
    Should Contain    ${output}    10.0.12.1/32    leaf3 should have BGP route to leaf2

Ping Spine1 To Leaf1 Loopback Should Succeed
    ${output}=    Run Ping Command    spine1    10.0.11.1    Loopback0    repeat=3
    Should Contain    ${output}    0% packet loss

Ping Spine1 To Leaf3 Loopback Should Succeed
    ${output}=    Run Ping Command    spine1    10.0.13.1    Loopback0    repeat=3
    Should Contain    ${output}    0% packet loss

Ping Spine1 To Spine2 Loopback Should Succeed
    ${output}=    Run Ping Command    spine1    10.0.2.1    Loopback0    repeat=3
    Should Contain    ${output}    0% packet loss

Ping Leaf1 To Leaf2 Loopback Should Succeed
    [Documentation]    Cross-spine leaf-to-leaf ping via ECMP.
    ${output}=    Run Ping Command    leaf1    10.0.12.1    Loopback0    repeat=3
    Should Contain    ${output}    0% packet loss

Ping Leaf1 To Leaf3 Loopback Should Succeed
    [Documentation]    Cross-spine leaf-to-leaf ping via ECMP.
    ${output}=    Run Ping Command    leaf1    10.0.13.1    Loopback0    repeat=3
    Should Contain    ${output}    0% packet loss

Ping Leaf3 To Spine2 Loopback Should Succeed
    ${output}=    Run Ping Command    leaf3    10.0.2.1    Loopback0    repeat=3
    Should Contain    ${output}    0% packet loss

Host1 Should Have Default Route Via Leaf1
    [Documentation]    Verify host1 has a default route pointing to leaf1.
    ${output}=    RTL.Run Host Show Route    host1
    Should Contain    ${output}    default via 10.3.1.0

Host2 Should Have Default Route Via Leaf2
    ${output}=    RTL.Run Host Show Route    host2
    Should Contain    ${output}    default via 10.3.2.0

Host3 Should Have Default Route Via Leaf3
    ${output}=    RTL.Run Host Show Route    host3
    Should Contain    ${output}    default via 10.3.3.0

Host1 Should Ping Spine1 Loopback
    ${output}=    RTL.Run Host Ping    host1    10.0.1.1    count=3
    Should Contain    ${output}    0% packet loss

Host1 Should Ping Leaf2 Loopback
    ${output}=    RTL.Run Host Ping    host1    10.0.12.1    count=3
    Should Contain    ${output}    0% packet loss

Host2 Should Ping Spine2 Loopback
    ${output}=    RTL.Run Host Ping    host2    10.0.2.1    count=3
    Should Contain    ${output}    0% packet loss

Host2 Should Ping Host3
    [Documentation]    Cross-host ping via the fabric.
    ${output}=    RTL.Run Host Ping    host2    10.3.3.1    count=3
    Should Contain    ${output}    0% packet loss

Host3 Should Ping Host1
    [Documentation]    Cross-host ping via the fabric.
    ${output}=    RTL.Run Host Ping    host3    10.3.1.1    count=3
    Should Contain    ${output}    0% packet loss

BFD Should Be Configured On Spine Interfaces
    [Documentation]    Verify BFD peers are configured on all Ethernet interfaces of spine nodes.
    FOR    ${node}    IN    spine1    spine2
        ${output}=    Run Show Command    ${node}    bfd peers
        ${bfd_count}=    Get Regexp Matches    ${output}    \\d+\\.\\d+\\.\\d+\\.\\d+
        Should Be True    len(${bfd_count}) >= 3    ${node} should have at least 3 BFD peers configured
    END

BFD Should Be Configured On Leaf Interfaces
    [Documentation]    Verify BFD peers are configured on spine-facing interfaces of leaf nodes.
    FOR    ${node}    IN    leaf1    leaf2    leaf3
        ${output}=    Run Show Command    ${node}    bfd peers
        ${bfd_count}=    Get Regexp Matches    ${output}    \\d+\\.\\d+\\.\\d+\\.\\d+
        Should Be True    len(${bfd_count}) >= 2    ${node} should have at least 2 BFD peers configured
    END

BFD Sessions Should Be Up On Spine Nodes
    [Documentation]    Verify BFD sessions are established on spine nodes.
    FOR    ${node}    IN    spine1    spine2
        ${output}=    Run Show Command    ${node}    bfd peers
        ${up_count}=    Get Regexp Matches    ${output}    (?i)Up
        Should Be True    len(${up_count}) >= 3    ${node} should have at least 3 BFD sessions up
    END

BFD Sessions Should Be Up On Leaf Nodes
    [Documentation]    Verify BFD sessions are established on leaf nodes (spine-facing interfaces).
    FOR    ${node}    IN    leaf1    leaf2    leaf3
        ${output}=    Run Show Command    ${node}    bfd peers
        ${up_count}=    Get Regexp Matches    ${output}    (?i)Up
        Should Be True    len(${up_count}) >= 2    ${node} should have at least 2 BFD sessions up (to spines)
    END

BGP Neighbors Should Have BFD Enabled On Spine1
    [Documentation]    Verify BFD is enabled for all BGP neighbors on spine1.
    ${output}=    Run Show Command    spine1    bgp neighbors
    FOR    ${neighbor_ip}    IN    @{SPINE1_NEIGHBORS}
        Should Contain    ${output}    ${neighbor_ip}    spine1 BGP neighbor ${neighbor_ip} should be present
    END
    ${bfd_count}=    Get Regexp Matches    ${output}    (?i)BFD.*enabled
    Length Should Be    ${bfd_count}    3    spine1 should have BFD enabled for 3 BGP neighbors

BGP Neighbors Should Have BFD Enabled On Spine2
    [Documentation]    Verify BFD is enabled for all BGP neighbors on spine2.
    ${output}=    Run Show Command    spine2    bgp neighbors
    FOR    ${neighbor_ip}    IN    @{SPINE2_NEIGHBORS}
        Should Contain    ${output}    ${neighbor_ip}    spine2 BGP neighbor ${neighbor_ip} should be present
    END
    ${bfd_count}=    Get Regexp Matches    ${output}    (?i)BFD.*enabled
    Length Should Be    ${bfd_count}    3    spine2 should have BFD enabled for 3 BGP neighbors

BGP Neighbors Should Have BFD Enabled On Leaf Nodes
    [Documentation]    Verify BFD is enabled for BGP neighbors on all leaf nodes.
    FOR    ${node}    IN    leaf1    leaf2    leaf3
        ${output}=    Run Show Command    ${node}    bgp neighbors
        ${bfd_count}=    Get Regexp Matches    ${output}    (?i)BFD.*enabled
        Length Should Be    ${bfd_count}    2    ${node} should have BFD enabled for 2 BGP neighbors
    END

BGP Router-ID Should Be Set On All EOS Nodes
    [Documentation]    Verify BGP router-id matches the loopback IP on all nodes.
    FOR    ${node}    ${expected_rid}    IN    spine1    10.0.1.1    spine2    10.0.2.1    leaf1    10.0.11.1    leaf2    10.0.12.1    leaf3    10.0.13.1
        ${output}=    Run Show Command    ${node}    bgp neighbors
        Should Contain    ${output}    ${expected_rid}    ${node} should have router-id ${expected_rid}
    END

BGP Address-Family IPv4 Should Be Active On Spine Nodes
    [Documentation]    Verify address-family ipv4 unicast is configured on spine nodes.
    FOR    ${node}    IN    spine1    spine2
        ${output}=    Run Show Command    ${node}    bgp summary
        Should Contain    ${output}    IPv4 Unicast    ${node} should have IPv4 Unicast address-family
    END

BGP Address-Family IPv4 Should Be Active On Leaf Nodes
    [Documentation]    Verify address-family ipv4 unicast is configured on leaf nodes.
    FOR    ${node}    IN    leaf1    leaf2    leaf3
        ${output}=    Run Show Command    ${node}    bgp summary
        Should Contain    ${output}    IPv4 Unicast    ${node} should have IPv4 Unicast address-family
    END

Lab Should Tear Down Successfully
    [Documentation]    Tear down the lab via netlab down.
    Netlab Down
