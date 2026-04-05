# Aspect Hierarchy: desktop-gdm

```mermaid
graph TD
  desktop_gdm([desktop-gdm]):::host
  host[host]
  workstation[workstation]
  networking[networking]
  tailscale[tailscale]
  desktop[desktop]
  regreet[regreet]:::replaced
  gdm[gdm]
  default[default]
  hostname[hostname]
  define_user[define-user]
  user[user]
  alice[user/alice]

  desktop_gdm --> host
  desktop_gdm --> workstation
  workstation --> networking
  workstation --> tailscale
  workstation --> desktop
  desktop -.->|replaced| regreet
  desktop --> gdm
  desktop_gdm --> default
  default --> hostname
  default --> define_user
  desktop_gdm --> user
  desktop_gdm --> alice

  classDef host fill:#4a9,stroke:#2d7,color:#fff,font-weight:bold
  classDef excluded fill:#f99,stroke:#f00,stroke-dasharray: 5 5
  classDef replaced fill:#ff9,stroke:#fa0
```
