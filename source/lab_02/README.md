## Udrelay OSPF
---
### Задание:
Настроить OSPF для Underlay сети.
---
### План работы
 - Распределить адресное пространство underlay сети.
 - Разработать конфигурацию устройств с использованием симулятора netlab.
 - Выполнить практическую часть - yбедится в наличии связности устройств в OSPF домене. 

### Решение
Распределение адресного пространства выполнено как в предыдущей работе:
**Используем рекомендованную схему ЦОД (2).**

**Топология CLOS:** 2 Spine + 3 Leaf 

**Формат адресации:** `10.Dn.Sn.X/31`
Где:
- **Dn** (Data Center number):
  - `0` = Loopback0
  - `1` = Loopback1
  - `2` = P2P линки
  - `3` = Зарезервировано
  - `4-7` = Services
- **Sn** (Номер Spine):
  - `1-2` = Spine switches
  - `11-13` = Leaf switches
- **X** = Sequential number (порядковыйй номер)

##### Интерфейсы Loopback

| Node | Interface | IP Address | Description |
|------|-----------|------------|-------------|
| spine1 | Loopback0 | 10.0.1.1/32 | Spine1-Loopback0 |
| spine1 | Loopback1 | 10.1.1.1/32 | Spine1-Loopback1 |
| spine2 | Loopback0 | 10.0.2.1/32 | Spine2-Loopback0 |
| spine2 | Loopback1 | 10.1.2.1/32 | Spine2-Loopback1 |
| leaf1 | Loopback0 | 10.0.11.1/32 | Leaf1-Loopback0 |
| leaf1 | Loopback1 | 10.1.11.1/32 | Leaf1-Loopback1 |
| leaf2 | Loopback0 | 10.0.12.1/32 | Leaf2-Loopback0 |
| leaf2 | Loopback1 | 10.1.12.1/32 | Leaf2-Loopback1 |
| leaf3 | Loopback0 | 10.0.13.1/32 | Leaf3-Loopback0 |
| leaf3 | Loopback1 | 10.1.13.1/32 | Leaf3-Loopback1 |

##### Point-to-Point линки

| Link | Node A Interface | Node A IP | Node B Interface | Node B IP |
|------|------------------|-----------|------------------|-----------|
| spine1-leaf1 | Ethernet1 | 10.2.1.0/31 | Ethernet1 | 10.2.1.1/31 |
| spine1-leaf2 | Ethernet2 | 10.2.1.2/31 | Ethernet1 | 10.2.1.3/31 |
| spine1-leaf3 | Ethernet3 | 10.2.1.4/31 | Ethernet1 | 10.2.1.5/31 |
| spine2-leaf1 | Ethernet1 | 10.2.2.0/31 | Ethernet2 | 10.2.2.1/31 |
| spine2-leaf2 | Ethernet2 | 10.2.2.2/31 | Ethernet2 | 10.2.2.3/31 |
| spine2-leaf3 | Ethernet3 | 10.2.2.4/31 | Ethernet2 | 10.2.2.5/31 |


### Маски подсетей:
- Loopback: `/32`
- P2P links: `/31`


**Перезагрузка ноды**
```
docker restart clab-tmp-leaf3
```
**Захват трафика**
```
sudo ip netns exec clab-tmp-leaf1 tcpdump -i et1 -U -w - | wireshark -k -i -
```

