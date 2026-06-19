*** Settings ***
Documentation    Packet capture tests — captures IS-IS and BFD packets on
...    live POD using docker exec + tcpdump, validates packet contents.
...    Lab lifecycle is managed via `netlab up` / `netlab down`.
Resource         NetlabCommon.resource
Library          Collections
Library          String
Library          re

Suite Setup      Netlab Up
Suite Teardown   Netlab Down

*** Variables ***
${CAPTURE_IFACE}       et1
${ISIS_FILTER}         ether proto 0x00FE
${BFD_FILTER}          udp port 3784

# Node MAC addresses (containerlab auto-assigned pattern ca:f0:00:<idx>:00:01)
${SPINE1_MAC}          ca:f0:00:01:00:01
${LEAF1_MAC}           ca:f0:00:03:00:01

*** Keywords ***
Count Matches
    [Arguments]    ${text}    ${pattern}
    ${matches}=    Get Regexp Matches    ${text}    ${pattern}
    ${count}=    Get Length    ${matches}
    RETURN    ${count}

*** Test Cases ***
IS-IS Hello Packets Should Be Captured On spine1
    [Documentation]    Capture IS-IS IIH (Hello) packets on spine1.
    ${output}=    RTL.Capture Packets    spine1    ${CAPTURE_IFACE}    ${ISIS_FILTER}    3    20
    Should Not Be Empty    ${output}    Should have captured IS-IS packets
    Should Contain    ${output}    p2p IIH    Should capture p2p IIH packets

IS-IS Hello Should Contain spine1 Source System ID
    [Documentation]    Verify IS-IS Hello from spine1 contains correct system ID.
    ${output}=    RTL.Capture Packets Verbose    spine1    ${CAPTURE_IFACE}    ${ISIS_FILTER}    10    30    src_mac=${SPINE1_MAC}
    ${has_iih}=    Get Regexp Matches    ${output}    (?i)p2p IIH[\\s\\S]{0,800}source-id: 0100\\.0000\\.1001
    ${count}=    Get Length    ${has_iih}
    Should Be True    ${count} > 0    IIH from spine1 should contain system-id 0100.0000.1001

IS-IS Hello Should Be Level 2 Only
    [Documentation]    Verify IS-IS Hello has Level-2 only flag set.
    ${output}=    RTL.Capture Packets Verbose    spine1    ${CAPTURE_IFACE}    ${ISIS_FILTER}    3    20
    ${has_iih_l2}=    Get Regexp Matches    ${output}    p2p IIH[\\s\\S]{0,300}Level 2 only
    ${count}=    Get Length    ${has_iih_l2}
    Should Be True    ${count} > 0    IIH should have Level 2 only flag

IS-IS Hello Should Contain Area Address 49.0001
    [Documentation]    Verify IS-IS Hello contains area address 49.0001.
    ${output}=    RTL.Capture Packets Verbose    spine1    ${CAPTURE_IFACE}    ${ISIS_FILTER}    3    20
    ${has_iih_area}=    Get Regexp Matches    ${output}    p2p IIH[\\s\\S]{0,500}Area address.*49\\.0001
    ${count}=    Get Length    ${has_iih_area}
    Should Be True    ${count} > 0    IIH should contain area address 49.0001

IS-IS Hello Should Advertise IPv4
    [Documentation]    Verify IS-IS Hello has NLPID IPv4.
    ${output}=    RTL.Capture Packets Verbose    spine1    ${CAPTURE_IFACE}    ${ISIS_FILTER}    3    20
    ${has_iih_ipv4}=    Get Regexp Matches    ${output}    p2p IIH[\\s\\S]{0,300}IPv4
    ${count}=    Get Length    ${has_iih_ipv4}
    Should Be True    ${count} > 0    IIH should advertise IPv4

IS-IS Hello From leaf1 Should Have Different System ID
    [Documentation]    Verify IS-IS Hello from leaf1 has different system ID.
    ${output}=    RTL.Capture Packets Verbose    leaf1    et1    ${ISIS_FILTER}    3    20
    ${has_iih}=    Get Regexp Matches    ${output}    p2p IIH[\\s\\S]{0,300}source-id: 0100\\.0001\\.1001
    ${count}=    Get Length    ${has_iih}
    Should Be True    ${count} > 0    IIH from leaf1 should contain system-id 0100.0001.1001

IS-IS CSNP Packets Should Be Captured
    [Documentation]    Capture IS-IS CSNP packets on spine1.
    ${output}=    RTL.Capture Packets    spine1    ${CAPTURE_IFACE}    ${ISIS_FILTER}    8    20
    Should Contain    ${output}    CSNP    Should capture CSNP packets

IS-IS CSNP Should Contain LSP Entries
    [Documentation]    Verify IS-IS CSNP contains LSP entry references.
    ${output}=    RTL.Capture Packets Verbose    spine1    ${CAPTURE_IFACE}    ${ISIS_FILTER}    8    20
    Should Contain    ${output}    CSNP    Should have CSNP packets
    Should Contain    ${output}    lsp-id    CSNP should contain lsp-id entries

BFD Packets Should Be Captured On spine1
    [Documentation]    Capture BFD control packets on spine1.
    ${output}=    RTL.Capture Packets    spine1    ${CAPTURE_IFACE}    ${BFD_FILTER}    5    10
    Should Not Be Empty    ${output}    Should have captured BFD packets
    ${count}=    Count Matches    ${output}    BFD
    Should Be True    ${count} >= 5    Should capture at least 5 BFD packets

BFD Packets Should Have State Up
    [Documentation]    Verify captured BFD packets have State Up.
    ${output}=    RTL.Capture Packets Verbose    spine1    ${CAPTURE_IFACE}    ${BFD_FILTER}    3    10
    Should Contain    ${output}    State Up    BFD packets should have State Up
    ${count}=    Count Matches    ${output}    State Up
    Should Be True    ${count} > 0    At least one BFD packet should be State Up

BFD Packets Should Use UDP Port 3784
    [Documentation]    Verify BFD packets use UDP port 3784.
    ${output}=    RTL.Capture Packets Verbose    spine1    ${CAPTURE_IFACE}    ${BFD_FILTER}    2    10
    Should Contain    ${output}    3784    BFD packets should use port 3784

BFD Packets Should Have Correct Timers
    [Documentation]    Verify BFD packet intervals are 100ms.
    ${output}=    RTL.Capture Packets Verbose    spine1    ${CAPTURE_IFACE}    ${BFD_FILTER}    2    10
    Should Contain    ${output}    Desired min Tx Interval:     100 ms
    Should Contain    ${output}    Required min Rx Interval:    100 ms

BFD Packets Should Have Multiplier 3
    [Documentation]    Verify BFD packet multiplier is 3.
    ${output}=    RTL.Capture Packets Verbose    spine1    ${CAPTURE_IFACE}    ${BFD_FILTER}    2    10
    Should Contain    ${output}    Multiplier: 3

BFD Packets Should Have TTL 255
    [Documentation]    Verify BFD packets have TTL 255 (security requirement).
    ${output}=    RTL.Capture Packets Verbose    spine1    ${CAPTURE_IFACE}    ${BFD_FILTER}    2    10
    Should Contain    ${output}    ttl 255    BFD packets should have TTL 255
