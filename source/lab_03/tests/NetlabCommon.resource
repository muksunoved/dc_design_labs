*** Settings ***
Documentation    Common variables and keywords for Netlab runtime tests.
Library          Collections
Library          String
Library          OperatingSystem
Library          Process
Library          re
Library          NetlabRuntimeLibrary.py    WITH NAME    RTL

*** Variables ***
${PROJECT_DIR}    %{PROJECT_DIR=.}

# All nodes
@{ALL_NODES}    spine1    spine2    leaf1    leaf2    leaf3

# Management IPs (for informational purposes, all access via netlab connect)
&{MGMT_IPS}
...    spine1=192.168.121.101
...    spine2=192.168.121.102
...    leaf1=192.168.121.103
...    leaf2=192.168.121.104
...    leaf3=192.168.121.105

# Expected loopback IPs
&{LOOPBACK_IPS}
...    spine1=10.0.1.1/32
...    spine2=10.0.2.1/32
...    leaf1=10.0.11.1/32
...    leaf2=10.0.12.1/32
...    leaf3=10.0.13.1/32

# Expected Ethernet interface counts
&{ETH_COUNTS}
...    spine1=3    spine2=3    leaf1=2    leaf2=2    leaf3=2

# BFD parameters
${BFD_INTERVAL}    100
${BFD_MIN_RX}      100
${BFD_MULTIPLIER}  3

*** Keywords ***
Netlab Up
    [Documentation]    Start the lab via `netlab up`.
    ...    Fails if any node is unreachable or config deployment fails.
    ${rc}    ${stdout}    ${stderr}=    RTL.Netlab Up    300
    Should Be Equal As Integers    ${rc}    0    netlab up failed: ${stderr}
    Should Contain    ${stdout}    OK    Lab should report OK

Netlab Down
    [Documentation]    Tear down the lab via `netlab down`.
    ${rc}    ${stdout}    ${stderr}=    RTL.Netlab Down    120
    # Don't fail teardown on netlab down errors
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
    [Documentation]    Run a multi-line CLI command (configure session) via `netlab connect`.
    [Arguments]    ${node}    ${command}
    ${output}=    RTL.Run CLI Command    ${node}    ${command}
    RETURN    ${output}

Bounce Interface
    [Documentation]    Shutdown then no-shutdown an interface on a node.
    [Arguments]    ${node}    ${interface}    ${wait_down}=5s    ${wait_up}=3s
    ${cmd_down}=    Catenate    SEPARATOR=\n    configure    interface ${interface}    shutdown    end
    ${cmd_up}=    Catenate    SEPARATOR=\n    configure    interface ${interface}    no shutdown    end
    Run CLI Command    ${node}    ${cmd_down}
    Sleep    ${wait_down}
    Run CLI Command    ${node}    ${cmd_up}
    Sleep    ${wait_up}
