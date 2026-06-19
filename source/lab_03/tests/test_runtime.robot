*** Settings ***
Documentation    Runtime tests — validates POD after `netlab up`:
...    - Lab lifecycle (netlab up / netlab down)
...    - Node version and reachability
...    - Interface status (up/up)
...    - IS-IS adjacencies (neighbors UP)
...    - IS-IS route exchange (all loopbacks learned)
...    - BFD sessions (state Up, correct timers)
...    - End-to-end ping (spine-to-leaf, leaf-to-leaf, leaf-to-spine)
Resource         NetlabCommon.resource
Library          Collections
Library          String
Library          re

Suite Setup      Netlab Up
Suite Teardown   Run Keywords    Wait For Topology To Stabilize    AND    Netlab Down

*** Keywords ***
Wait For Topology To Stabilize
    [Documentation]    Wait for adjacencies to fully establish after lab startup.
    Sleep    30s    Wait for IS-IS adjacencies and BFD sessions

Verify All Nodes Respond
    [Documentation]    Verify all nodes respond with correct version.
    FOR    ${node}    IN    @{ALL_NODES}
        ${output}=    Run Show Command    ${node}    version
        Should Contain    ${output}    Arista    ${node} should be running Arista cEOS
        Should Contain    ${output}    4.34.2.2F    ${node} should run correct image version
    END

*** Test Cases ***
Lab Should Start Successfully
    [Documentation]    Verified by Suite Setup (netlab up).
    Pass Execution    Lab started successfully

All Nodes Should Run Arista cEOS
    Verify All Nodes Respond

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
        Length Should Be    ${up_count}    2    ${node} should have 2 Ethernet interfaces up/up
    END

Loopback0 Should Have Correct IP On All Nodes
    [Documentation]    Verify Loopback0 IP matches the IP plan.
    FOR    ${node}    ${expected_ip}    IN    &{LOOPBACK_IPS}
        ${output}=    Run Show Command    ${node}    ip interface brief
        Should Contain    ${output}    ${expected_ip}    ${node} Loopback0 should be ${expected_ip}
    END

Loopback0 Should Be Up On All Nodes
    [Documentation]    Verify Loopback0 interface status is up/up.
    FOR    ${node}    IN    @{ALL_NODES}
        ${output}=    Run Show Command    ${node}    ip interface brief
        ${match}=    Get Regexp Matches    ${output}    Loopback0.*up.*up
        Length Should Be    ${match}    1    ${node} Loopback0 should be up
    END

IS-IS Neighbors Should Be UP On Spine1
    [Documentation]    spine1 should see leaf1, leaf2, leaf3 as UP neighbors.
    ${output}=    Run Show Command    spine1    isis neighbors
    Should Contain    ${output}    leaf1
    Should Contain    ${output}    leaf2
    Should Contain    ${output}    leaf3
    ${up_count}=    Get Regexp Matches    ${output}    (?i)\\bUP\\b
    Length Should Be    ${up_count}    3

IS-IS Neighbors Should Be UP On Spine2
    [Documentation]    spine2 should see leaf1, leaf2, leaf3 as UP neighbors.
    ${output}=    Run Show Command    spine2    isis neighbors
    Should Contain    ${output}    leaf1
    Should Contain    ${output}    leaf2
    Should Contain    ${output}    leaf3
    ${up_count}=    Get Regexp Matches    ${output}    (?i)\\bUP\\b
    Length Should Be    ${up_count}    3

IS-IS Neighbors Should Be UP On Leaf1
    [Documentation]    leaf1 should see spine1 and spine2 as UP neighbors.
    ${output}=    Run Show Command    leaf1    isis neighbors
    Should Contain    ${output}    spine1
    Should Contain    ${output}    spine2
    ${up_count}=    Get Regexp Matches    ${output}    (?i)\\bUP\\b
    Length Should Be    ${up_count}    2

IS-IS Neighbors Should Be UP On Leaf2
    [Documentation]    leaf2 should see spine1 and spine2 as UP neighbors.
    ${output}=    Run Show Command    leaf2    isis neighbors
    Should Contain    ${output}    spine1
    Should Contain    ${output}    spine2
    ${up_count}=    Get Regexp Matches    ${output}    (?i)\\bUP\\b
    Length Should Be    ${up_count}    2

IS-IS Neighbors Should Be UP On Leaf3
    [Documentation]    leaf3 should see spine1 and spine2 as UP neighbors.
    ${output}=    Run Show Command    leaf3    isis neighbors
    Should Contain    ${output}    spine1
    Should Contain    ${output}    spine2
    ${up_count}=    Get Regexp Matches    ${output}    (?i)\\bUP\\b
    Length Should Be    ${up_count}    2

IS-IS Process Should Be Named CORE On All Nodes
    [Documentation]    Verify IS-IS instance name is CORE.
    FOR    ${node}    IN    @{ALL_NODES}
        ${output}=    Run Show Command    ${node}    isis neighbors
        Should Contain    ${output}    CORE    ${node} IS-IS instance should be CORE
    END

IS-IS Should Distribute Routes On Spine1
    [Documentation]    spine1 should have IS-IS routes to spine2 and all leaf loopbacks.
    ${output}=    Run Show Command    spine1    ip route isis
    Should Contain    ${output}    10.0.2.1/32    spine1 should have route to spine2
    Should Contain    ${output}    10.0.11.1/32    spine1 should have route to leaf1
    Should Contain    ${output}    10.0.12.1/32    spine1 should have route to leaf2
    Should Contain    ${output}    10.0.13.1/32    spine1 should have route to leaf3
    # spine1 should also see spine2-leaf /31 networks
    Should Contain    ${output}    10.2.2.0/31    spine1 should have route to spine2-leaf1
    Should Contain    ${output}    10.2.2.2/31    spine1 should have route to spine2-leaf2
    Should Contain    ${output}    10.2.2.4/31    spine1 should have route to spine2-leaf3

IS-IS Should Distribute Routes On Leaf1
    [Documentation]    leaf1 should have routes to spines and other leaves.
    ${output}=    Run Show Command    leaf1    ip route isis
    Should Contain    ${output}    10.0.1.1/32    leaf1 should have route to spine1
    Should Contain    ${output}    10.0.2.1/32    leaf1 should have route to spine2
    Should Contain    ${output}    10.0.12.1/32    leaf1 should have route to leaf2
    Should Contain    ${output}    10.0.13.1/32    leaf1 should have route to leaf3

IS-IS Should Distribute Routes On Leaf3
    [Documentation]    leaf3 should have routes to spines and other leaves.
    ${output}=    Run Show Command    leaf3    ip route isis
    Should Contain    ${output}    10.0.1.1/32    leaf3 should have route to spine1
    Should Contain    ${output}    10.0.2.1/32    leaf3 should have route to spine2
    Should Contain    ${output}    10.0.11.1/32    leaf3 should have route to leaf1
    Should Contain    ${output}    10.0.12.1/32    leaf3 should have route to leaf2

BFD Sessions Should Be Up On Spine1
    [Documentation]    spine1 should have 3 BFD sessions to leaves.
    ${output}=    Run Show Command    spine1    bfd peers
    Should Contain    ${output}    10.2.1.1    BFD to leaf1
    Should Contain    ${output}    10.2.1.3    BFD to leaf2
    Should Contain    ${output}    10.2.1.5    BFD to leaf3
    # The "State" column shows "Up" — count standalone "Up" words after the header
    ${up_count}=    Get Regexp Matches    ${output}    (?m)\\bUp\\s*$
    Length Should Be    ${up_count}    3

BFD Sessions Should Be Up On Leaf1
    [Documentation]    leaf1 should have 2 BFD sessions to spines.
    ${output}=    Run Show Command    leaf1    bfd peers
    Should Contain    ${output}    10.2.1.0    BFD to spine1
    Should Contain    ${output}    10.2.2.0    BFD to spine2
    ${up_count}=    Get Regexp Matches    ${output}    (?m)\\bUp\\s*$
    Length Should Be    ${up_count}    2

BFD Sessions Should Be Up On Spine2
    [Documentation]    spine2 should have 3 BFD sessions to leaves.
    ${output}=    Run Show Command    spine2    bfd peers
    Should Contain    ${output}    10.2.2.1    BFD to leaf1
    Should Contain    ${output}    10.2.2.3    BFD to leaf2
    Should Contain    ${output}    10.2.2.5    BFD to leaf3
    ${up_count}=    Get Regexp Matches    ${output}    (?m)\\bUp\\s*$
    Length Should Be    ${up_count}    3

BFD Timers Should Be 100ms Interval With Multiplier 3 On Spine1
    [Documentation]    Verify BFD intervals match expected values.
    ${output}=    Run Show Command    spine1    bfd peers detail
    Should Contain    ${output}    TxInt: ${BFD_INTERVAL} ms
    Should Contain    ${output}    RxInt: ${BFD_MIN_RX} ms
    Should Contain    ${output}    Multiplier: ${BFD_MULTIPLIER}

BFD Should Be Registered With IS-IS On Leaf1
    [Documentation]    Verify BFD is registered with IS-IS protocol.
    ${output}=    Run Show Command    leaf1    bfd peers detail
    Should Contain    ${output}    Registered protocols: isis

Ping spine1 To leaf1 Loopback Should Succeed
    ${output}=    Run Ping Command    spine1    10.0.11.1    Loopback0    repeat=3
    Should Contain    ${output}    0% packet loss

Ping spine1 To leaf3 Loopback Should Succeed
    ${output}=    Run Ping Command    spine1    10.0.13.1    Loopback0    repeat=3
    Should Contain    ${output}    0% packet loss

Ping spine1 To spine2 Loopback Should Succeed
    ${output}=    Run Ping Command    spine1    10.0.2.1    Loopback0    repeat=3
    Should Contain    ${output}    0% packet loss

Ping leaf1 To leaf2 Loopback Should Succeed
    [Documentation]    Cross-spine leaf-to-leaf ping via ECMP.
    ${output}=    Run Ping Command    leaf1    10.0.12.1    Loopback0    repeat=3
    Should Contain    ${output}    0% packet loss

Ping leaf1 To leaf3 Loopback Should Succeed
    [Documentation]    Cross-spine leaf-to-leaf ping via ECMP.
    ${output}=    Run Ping Command    leaf1    10.0.13.1    Loopback0    repeat=3
    Should Contain    ${output}    0% packet loss

Ping leaf3 To spine2 Loopback Should Succeed
    ${output}=    Run Ping Command    leaf3    10.0.2.1    Loopback0    repeat=3
    Should Contain    ${output}    0% packet loss

Lab Should Tear Down Successfully
    [Documentation]    Verified by Suite Teardown (netlab down).
    Pass Execution    Lab torn down successfully
