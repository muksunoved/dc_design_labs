*** Settings ***
Documentation    Common variables and keywords for Netlab VXLAN EVPN runtime tests.
Library          Collections
Library          String
Library          OperatingSystem
Library          Process
Library          re
Library          NetlabRuntimeLibrary.py    WITH NAME    RTL

*** Variables ***
${PROJECT_DIR}    %{PROJECT_DIR=.}

# All EOS nodes
@{ALL_NODES}    spine1    spine2    leaf1    leaf2    leaf3

# All nodes including hosts
@{ALL_NODES_WITH_HOSTS}    spine1    spine2    leaf1    leaf2    leaf3    host1    host2    host3

# Leaf nodes only
@{LEAF_NODES}    leaf1    leaf2    leaf3

# Spine nodes only
@{SPINE_NODES}    spine1    spine2

# Host nodes only
@{HOST_NODES}    host1    host2    host3

# BGP AS numbers
&{BGP_AS}
...    spine1=65001    spine2=65002
...    leaf1=65101    leaf2=65102    leaf3=65103

# Expected loopback IPs (EOS nodes only) — VTEP IPs
&{LOOPBACK_IPS}
...    spine1=10.0.1.1/32    spine2=10.0.2.1/32
...    leaf1=10.0.11.1/32    leaf2=10.0.12.1/32    leaf3=10.0.13.1/32

# VTEP IPs (without prefix) for EVPN RD verification
&{VTEP_IPS}
...    leaf1=10.0.11.1    leaf2=10.0.12.1    leaf3=10.0.13.1

# Expected Ethernet interface counts (spine=3, leaf=3 including host link)
&{ETH_COUNTS}
...    spine1=3    spine2=3    leaf1=3    leaf2=3    leaf3=3

# Overlay parameters
${OVERLAY_VLAN}    10
${OVERLAY_VNI}    10010
${OVERLAY_RT}     10:10010
${OVERLAY_SUBNET}    192.168.10.0/24

# Overlay host IPs
&{HOST_OVERLAY_IPS}
...    host1=192.168.10.11    host2=192.168.10.12    host3=192.168.10.13

# P2P link subnets for BGP neighbor verification
@{SPINE1_NEIGHBORS}
...    10.2.1.1    10.2.1.3    10.2.1.5

@{SPINE2_NEIGHBORS}
...    10.2.2.1    10.2.2.3    10.2.2.5

@{LEAF1_NEIGHBORS}
...    10.2.1.0    10.2.2.0

@{LEAF2_NEIGHBORS}
...    10.2.1.2    10.2.2.2

@{LEAF3_NEIGHBORS}
...    10.2.1.4    10.2.2.4

# BFD parameters
${BFD_INTERVAL}    100
${BFD_MIN_RX}      100
${BFD_MULTIPLIER}  3

*** Keywords ***
Netlab Up
    [Documentation]    Start the lab via `netlab up`.
    ${rc}    ${stdout}    ${stderr}=    RTL.Netlab Up    300
    Should Be Equal As Integers    ${rc}    0    netlab up failed: ${stderr}
    Should Contain    ${stdout}    OK    Lab should report OK

Netlab Down
    [Documentation]    Tear down the lab via `netlab down`.
    ${rc}    ${stdout}    ${stderr}=    RTL.Netlab Down    120
    Run Keyword If    ${rc} != 0
    ...    Log    netlab down returned rc=${rc}: ${stderr}    WARN

Run Show Command
    [Documentation]    Run `netlab connect <node> --show <cmd>` and return output.
    [Arguments]    ${node}    ${command}
    ${output}=    RTL.Run Show Command    ${node}    ${command}
    RETURN    ${output}

Run Ping Command
    [Documentation]    Ping from a node via `netlab connect`.
    [Arguments]    ${node}    ${target_ip}    ${source}    ${repeat}=3
    ${output}=    RTL.Run Ping    ${node}    ${target_ip}    ${source}    ${repeat}
    RETURN    ${output}

Run CLI Command
    [Documentation]    Run a multi-line CLI command via netlab connect.
    [Arguments]    ${node}    ${command}
    ${output}=    RTL.Run CLI Command    ${node}    ${command}
    RETURN    ${output}

Run Host Ping
    [Documentation]    Ping from a Linux host container via docker exec.
    [Arguments]    ${host}    ${target_ip}    ${count}=3
    ${output}=    RTL.Run Host Ping    ${host}    ${target_ip}    ${count}
    RETURN    ${output}

Run Host Command
    [Documentation]    Run a command inside a host container via docker exec.
    [Arguments]    ${host}    ${command}
    ${output}=    RTL.Run Host Command    ${host}    ${command}
    RETURN    ${output}

Verify EOS Loopback
    [Documentation]    Verify Loopback0 IP on an EOS node.
    [Arguments]    ${node}    ${expected_ip}
    ${output}=    Run Show Command    ${node}    ip interface brief
    Should Contain    ${output}    ${expected_ip}    ${node} Loopback0 should be ${expected_ip}
