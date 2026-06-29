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

# Expected Ethernet interface counts (spine=3, leaf=3 including host link)
&{ETH_COUNTS}
...    spine1=3    spine2=3    leaf1=3    leaf2=3    leaf3=3

# BFD parameters
${BFD_INTERVAL}    100
${BFD_MIN_RX}      100
${BFD_MULTIPLIER}  3

*** Keywords ***
Load IP Plan Variables
    [Documentation]    Load IP addresses from ip-plan.yml and set as suite variables.
    ...    Variables are stored as Python dicts/lists and accessed via ${VAR}[key].
    ${ip_plan}=    RTL.Load IP Plan
    Set Suite Variable    ${LOOPBACK_IPS}    ${ip_plan}[loopback_ips]
    Set Suite Variable    ${VTEP_IPS}    ${ip_plan}[vtep_ips]
    Set Suite Variable    ${HOST_OVERLAY_IPS}    ${ip_plan}[host_overlay_ips]
    Set Suite Variable    ${SPINE1_NEIGHBORS}    ${ip_plan}[neighbors][spine1]
    Set Suite Variable    ${SPINE2_NEIGHBORS}    ${ip_plan}[neighbors][spine2]
    Set Suite Variable    ${LEAF1_NEIGHBORS}    ${ip_plan}[neighbors][leaf1]
    Set Suite Variable    ${LEAF2_NEIGHBORS}    ${ip_plan}[neighbors][leaf2]
    Set Suite Variable    ${LEAF3_NEIGHBORS}    ${ip_plan}[neighbors][leaf3]
    Set Suite Variable    ${OVERLAY_VLAN}    ${{str(${ip_plan}[overlay][vlan])}}
    Set Suite Variable    ${OVERLAY_VNI}    ${{str(${ip_plan}[overlay][vni])}}
    Set Suite Variable    ${OVERLAY_RT}    ${ip_plan}[overlay][rt]
    Set Suite Variable    ${OVERLAY_SUBNET}    ${ip_plan}[overlay][subnet]

Check Rootless Prerequisites
    [Documentation]    Verify rootless containerlab setup before running tests.
    ...    Fails with a link to setup/README.md if prerequisites are not met.
    RTL.Check Rootless Prerequisites

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

Count Matches
    [Documentation]    Count regex matches in text.
    [Arguments]    ${text}    ${pattern}
    ${matches}=    Get Regexp Matches    ${text}    ${pattern}
    ${count}=    Get Length    ${matches}
    RETURN    ${count}

Capture Packets
    [Documentation]    Capture packets on a node interface.
    [Arguments]    ${node}    ${interface}    ${bpf_filter}    ${count}    ${timeout}=30
    ${output}=    RTL.Capture Packets    ${node}    ${interface}    ${bpf_filter}    ${count}    ${timeout}
    RETURN    ${output}

Capture Packets Verbose
    [Documentation]    Capture packets with verbose output on a node interface.
    [Arguments]    ${node}    ${interface}    ${bpf_filter}    ${count}    ${timeout}=30    ${src_mac}=NONE
    ${output}=    RTL.Capture Packets Verbose    ${node}    ${interface}    ${bpf_filter}    ${count}    ${timeout}    src_mac=${src_mac}
    RETURN    ${output}

Bounce Interface
    [Documentation]    Shutdown then no-shutdown an EOS interface.
    [Arguments]    ${node}    ${interface}    ${wait_down}=5    ${wait_up}=3
    RTL.Bounce Interface    ${node}    ${interface}    ${wait_down}    ${wait_up}
