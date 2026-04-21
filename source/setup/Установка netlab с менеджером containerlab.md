
#### Установка для Ubuntu 24.04

Самый простой вариант (ubuntu 24.04):
```shell
$ pipx install networklab
```

##### Установка containerlab
Для `ubuntu/linux` настоятельно рекомендуется использовать `containerlab`
```shell
$ netlab install containerlab
```
При установке будет в систему будет установлен docker.
Текущий пользователь будет добавлен в группу docker. Поэтому потребуется перелогинится или перезагрузиться.

При необходимости можно доапгрейдить пакет до последней версии (в окументации написано что тестировался с версией 0.72.0):
```shell
$ sudo containerlab version upgrade
...
	A newer containerlab 0.74.3 is available. Release notes:
	https://containerlab.dev/rn/0.74/#0743
	You are running containerlab 0.72.0 version
	Downloading https://github.com/srl-labs/containerlab/releases/download/v0.74.3/containerlab_0.74.3_linux_amd64.deb
	Preparing to install containerlab 0.74.3 from package
	(Reading database ... 265322 files and directories currently installed.)
	Preparing to unpack .../containerlab_0.74.3_linux_amd64.deb ...
	Unpacking containerlab (0.74.3) over (0.72.0) ...
	Setting up containerlab (0.74.3) ...
	
	...
	
	    version: 0.74.3
	     commit: 7eadb290a
	       date: 2026-03-24T10:00:24Z
	     source: https://github.com/srl-labs/containerlab
	 rel. notes: https://containerlab.dev/rn/0.74/#0743
```

Проверка поддерживаемых образов:
```shell
$ netlab show images
```

##### Установка `ansible`
`Netlab` требует определенной версии, поэтому если в системе уже установлен `ansible` следует его удалить и установить командой:
```shell
$ netlab install ansible
```

##### Установка визуализации
```
$ netlab install graph
```

##### Установка контейнера `Arista cEOS` для `containerlab`
Качаем контейнер с сайта: https://www.arista.com/en/support/software-download
Для регистрации потребуется корпоративный почтовый ящик и доступ не из зоны RU.
Распаковываем и устанавливаем:
```shell
$ docker image import <tar-filename> <tag>

пример
$ docker image import ./cEOS-lab-4.34.2.2F.tar ceos:4.34.2.2F
```

##### Подготовка тестового запуска
Создать каталог для лабы и поместить туда файл с содержанием (для версии контейнера из примера):
```yaml
---
provider: clab

defaults:
  devices.eos.clab.image: "ceos:4.34.2.2F"
  device: eos

module: [ ospf ]

ospf:
  area: "0.0.0.1"

nodes: [ r1, r2 ]

links:
- r1:
  r2:
  ospf:
    area: 0.0.0.1
```

Необходимо изменить системные переменные `sysctl`:
```
$ sudo sysctl net.bridge.bridge-nf-call-ip6tables=0
$ sudo sysctl net.bridge.bridge-nf-call-iptables=0
$ sudo sysctl net.bridge.bridge-nf-call-arptables=0
```

В этом же каталоге выполняем запуск лабы:
```shell
$ netlab up

или, если требуется более подробный вывод

$ netlab up -vv
```
Если запуск прошел успешно увидим в консоли:
```shell
[SUCCESS] Lab devices configured
```
Далее можно посмотреть трафик для ноды `r1` или `r2`:
```shell
$ netlab capture r1 Ethernet1
$ netlab capture r2 Ethernet1

```

Примерный вывод (видим анонсы `OSPF` и `LLDP`):
```shell
Starting packet capture on r1/et1: sudo ip netns exec clab-testing2-r1 tcpdump -i et1 --immediate-mode -l -vv
tcpdump: listening on et1, link-type EN10MB (Ethernet), snapshot length 262144 bytes
19:32:42.434115 IP (tos 0xc0, ttl 1, id 29099, offset 0, flags [DF], proto OSPF (89), length 68)
    10.1.0.1 > 224.0.0.5: OSPFv2, Hello, length 48
	Router-ID 10.0.0.1, Area 0.0.0.1, Authentication Type: none (0)
	Options [External]
	  Hello Timer 10s, Dead Timer 40s, Mask 255.255.255.252, Priority 0
	  Neighbor List:
	    10.0.0.2
19:32:44.989551 IP (tos 0xc0, ttl 1, id 62427, offset 0, flags [DF], proto OSPF (89), length 68)
    10.1.0.2 > 224.0.0.5: OSPFv2, Hello, length 48
	Router-ID 10.0.0.2, Area 0.0.0.1, Authentication Type: none (0)
	Options [External]
	  Hello Timer 10s, Dead Timer 40s, Mask 255.255.255.252, Priority 0
	  Neighbor List:
	    10.0.0.1
19:32:48.922812 LLDP, length 230
	Chassis ID TLV (1), length 7
	  Subtype MAC address (4): 00:1c:73:18:d3:4d (oui Unknown)
	  0x0000:  0400 1c73 18d3 4d
```

Также можно записать файл для wireshark: 
Смотрим какие ноды присутствуют:
```shell
$ ip netns list
...
clab-testing2-r1
clab-testing2-r2
```
Запускаем для выбранной ноды (см. вывод из консоли выше для команды `netlink capture`):
```shell
$ sudo ip netns exec clab-testing2-r1 tcpdump -vvi et1 -w ./out.pcap
```
Полученный файл открываем в `wireshark`
![[test-pcap-wireshark.png]]




Сформируем картинку с топологией:
```shell
$ netlab graph
$ dot graph.dot -T png -o test-topo.png
```

![[test-topo.png]]

Подробнее см. : https://blog.ipspace.net/2021/09/netsim-tools-graphs/

Остановка лабы:
```shell
$ netlab down
```


