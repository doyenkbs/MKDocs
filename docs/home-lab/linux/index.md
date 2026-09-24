---
tags:
  - Linux
---

# Linux

Enterprise Linux notes from the lab: building the systems, registering them, keeping them patched, and fixing what breaks.

## Red Hat Enterprise Linux

<div class="k-rack" markdown>

-   [
    <span class="k-rack-code">Rhel</span>
    <span class="k-rack-title">RHEL on Proxmox</span>
    <span class="k-rack-desc">Getting RHEL at no cost, building the VM, registering the subscription, Cockpit, and the kernel patching workflow.</span>
    <span class="k-rack-go">&rarr;</span>
    ](rhel/rhel-lab.md){ .k-rack-row }

</div>

## Why real RHEL

Rocky Linux and AlmaLinux are binary compatible rebuilds and cost nothing to run. What they do not give you is `subscription-manager`, Red Hat errata, or the entitlement model, and those are exactly the parts that show up in enterprise vulnerability remediation work.

A free Developer Subscription for Individuals covers up to 16 systems, which is more than a home lab needs.
