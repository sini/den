# Aspect Hierarchy: devbox

```mermaid
graph TD
  devbox([devbox]):::host
  host[host]
  workstation[workstation]
  networking[networking]
  tailscale[tailscale]:::excluded
  desktop[desktop]
  regreet[regreet]
  server[server]
  monitoring[monitoring]
  node_exporter[monitoring/node-exporter]
  default[default]
  hostname[hostname]
  define_user[define-user]
  user[user]
  alice[user/alice]

  devbox --> host
  devbox --> workstation
  workstation --> networking
  workstation -.-x tailscale
  workstation --> desktop
  desktop --> regreet
  devbox --> server
  server --> networking
  server --> monitoring
  server --> node_exporter
  server -.-x tailscale
  devbox --> default
  default --> hostname
  default --> define_user
  devbox --> user
  devbox --> alice

  classDef host fill:#4a9,stroke:#2d7,color:#fff,font-weight:bold
  classDef excluded fill:#f99,stroke:#f00,stroke-dasharray: 5 5
  classDef replaced fill:#ff9,stroke:#fa0
```
