# C4 Component View: mail-relay

![C4 Component](./mail-relay-c4component.puml.svg)

```plantuml
@startuml
!include <C4/C4_Component>
skinparam backgroundColor #1e1e2e
skinparam defaultFontColor #cdd6f4
skinparam defaultFontName "JetBrains Mono,monospace"
skinparam arrowColor #a6adc8
skinparam arrowFontColor #cdd6f4
skinparam PersonBackgroundColor #313244
skinparam PersonBorderColor #a6adc8
skinparam PersonFontColor #cdd6f4
skinparam SystemBackgroundColor #313244
skinparam SystemBorderColor #a6adc8
skinparam SystemFontColor #cdd6f4
skinparam ContainerBackgroundColor #313244
skinparam ContainerBorderColor #a6adc8
skinparam ContainerFontColor #cdd6f4
skinparam ComponentBackgroundColor #313244
skinparam ComponentBorderColor #a6adc8
skinparam ComponentFontColor #cdd6f4
skinparam BoundaryBackgroundColor #313244
skinparam BoundaryBorderColor #6c7086
skinparam BoundaryFontColor #cdd6f4
skinparam RectangleBackgroundColor #313244
skinparam RectangleBorderColor #a6adc8
skinparam RectangleFontColor #cdd6f4


title Component view: mail-relay

System_Boundary(mail_relay, "mail-relay") {
  Container_Boundary(host, "host") {
    Component(monitoring__alerting, "monitoring/alerting", "nixos")
    Component(backup, "backup", "")
    Component(virtualization__docker, "virtualization/docker", "nixos")
    Component(mail, "mail", "")
    Component(monitoring, "monitoring", "nixos")
    Component(networking, "networking", "nixos")
    Component(monitoring__nginx_exporter, "monitoring/nginx-exporter", "nixos")
    Component(monitoring__node_exporter, "monitoring/node-exporter", "nixos")
    Component(relay, "relay", "")
    Component(server, "server", "")
    Component(tailscale, "tailscale", "nixos")
    Component(virtualization, "virtualization", "nixos")
}
  Container_Boundary(c4_default, "default") {
    Component(den__provides__define_user, "provides/define-user", "")
    Component(den__provides__hostname, "provides/hostname", "")
    Component(den__provides__mutual_provider, "provides/mutual-provider", "")
}
  Container_Boundary(user, "user") {
    Component(deploy, "deploy", "homeManager+nixos")
}
}

Rel(backup, mail, "includes")
Rel(backup, relay, "includes")
Rel(backup, server, "includes")
Rel(den__provides__mutual_provider, den__provides__define_user, "includes")
Rel(den__provides__mutual_provider, den__provides__hostname, "includes")
Rel(den__provides__hostname, den__provides__define_user, "includes")
Rel(den__provides__define_user, den__provides__hostname, "includes")
Rel(den__provides__define_user, den__provides__mutual_provider, "includes")
Rel(den__provides__hostname, den__provides__mutual_provider, "includes")
Rel(mail, backup, "includes")
Rel(monitoring, backup, "includes")
Rel(monitoring__alerting, backup, "includes")
Rel(monitoring__nginx_exporter, backup, "includes")
Rel(monitoring__node_exporter, backup, "includes")
Rel(networking, backup, "includes")
Rel(relay, backup, "includes")
Rel(server, backup, "includes")
Rel(tailscale, backup, "includes")
Rel(virtualization, backup, "includes")
Rel(virtualization__docker, backup, "includes")
Rel(monitoring, mail, "includes")
Rel(monitoring__alerting, mail, "includes")
Rel(monitoring__nginx_exporter, mail, "includes")
Rel(monitoring__node_exporter, mail, "includes")
Rel(networking, mail, "includes")
Rel(relay, mail, "includes")
Rel(server, mail, "includes")
Rel(tailscale, mail, "includes")
Rel(virtualization, mail, "includes")
Rel(virtualization__docker, mail, "includes")
Rel(mail, relay, "includes")
Rel(monitoring, relay, "includes")
Rel(monitoring__alerting, relay, "includes")
Rel(monitoring__nginx_exporter, relay, "includes")
Rel(monitoring__node_exporter, relay, "includes")
Rel(networking, relay, "includes")
Rel(server, relay, "includes")
Rel(tailscale, relay, "includes")
Rel(virtualization, relay, "includes")
Rel(virtualization__docker, relay, "includes")
Rel(monitoring, monitoring__node_exporter, "includes")
Rel(monitoring__alerting, tailscale, "includes")
Rel(monitoring__nginx_exporter, monitoring__alerting, "includes")
Rel(monitoring__node_exporter, monitoring__nginx_exporter, "includes")
Rel(networking, monitoring, "includes")
Rel(relay, networking, "includes")
Rel(relay, server, "includes")
Rel(server, monitoring__alerting, "includes")
Rel(server, virtualization__docker, "includes")
Rel(server, monitoring, "includes")
Rel(server, networking, "includes")
Rel(server, monitoring__nginx_exporter, "includes")
Rel(server, monitoring__node_exporter, "includes")
Rel(server, tailscale, "includes")
Rel(server, virtualization, "includes")
Rel(tailscale, virtualization, "includes")
Rel(virtualization, virtualization__docker, "includes")
@enduml
```
