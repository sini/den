# C4 Component View: provider-filter

![C4 Component](./provider-filter-c4component.puml.svg)

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


title Component view: provider-filter

System_Boundary(provider_filter, "provider-filter") {
  Container_Boundary(host, "host") {
    Component(monitoring__alerting, "monitoring/alerting", "nixos")
    Component(backup, "backup", "")
    Component(virtualization__docker, "virtualization/docker", "nixos")
    Component(monitoring, "monitoring", "nixos")
    Component(networking, "networking", "nixos")
    Component(monitoring__nginx_exporter, "monitoring/nginx-exporter", "nixos")
    Component(monitoring__node_exporter, "monitoring/node-exporter", "nixos")
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

Rel(backup, server, "includes")
Rel(den__provides__mutual_provider, den__provides__define_user, "includes")
Rel(den__provides__mutual_provider, den__provides__hostname, "includes")
Rel(den__provides__hostname, den__provides__define_user, "includes")
Rel(den__provides__define_user, den__provides__hostname, "includes")
Rel(den__provides__define_user, den__provides__mutual_provider, "includes")
Rel(den__provides__hostname, den__provides__mutual_provider, "includes")
Rel(monitoring, backup, "includes")
Rel(monitoring__alerting, backup, "includes")
Rel(monitoring__nginx_exporter, backup, "includes")
Rel(monitoring__node_exporter, backup, "includes")
Rel(networking, backup, "includes")
Rel(server, backup, "includes")
Rel(tailscale, backup, "includes")
Rel(virtualization, backup, "includes")
Rel(virtualization__docker, backup, "includes")
Rel(monitoring, server, "includes")
Rel(monitoring__alerting, server, "includes")
Rel(monitoring__nginx_exporter, server, "includes")
Rel(monitoring__node_exporter, server, "includes")
Rel(networking, server, "includes")
Rel(tailscale, server, "includes")
Rel(virtualization, server, "includes")
Rel(virtualization__docker, server, "includes")
Rel(monitoring, monitoring__node_exporter, "includes")
Rel(monitoring__alerting, tailscale, "includes")
Rel(monitoring__nginx_exporter, monitoring__alerting, "includes")
Rel(monitoring__node_exporter, monitoring__nginx_exporter, "includes")
Rel(networking, monitoring, "includes")
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
