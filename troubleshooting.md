# Troubleshooting

## `make deploy_sno` fails at "Assert boot override is set" (Dell iDRAC9)

### Symptom

The deploy runs successfully through bare-metal prep — agent ISO generated and
served, VirtualMedia inserted via Redfish, UEFI boot target validated, one-time
boot override set — then aborts on the very next task:

```
TASK [bm_sno : Assert boot override is set]
fatal: The conditional
  '_boot_verify.json.Boot.UefiTargetBootSourceOverride | default('') | length > 0'
  failed: object of type 'NoneType' has no len().
```

Progress observed before the failure:

- Agent ISO generated, served at `http://<SNO_CONTROLLER_IP>:80/agent.x86_64.iso`
- VirtualMedia ejected + agent ISO inserted via Redfish
- UEFI boot target validated (Virtual Optical Drive)
- One-time boot override set ("Set one-time boot from Virtual Optical Drive" → ok)
- ❌ "Assert boot override is set" crashed

### Affected hardware

Observed on:

| Field | Value |
|---|---|
| iDRAC | iDRAC9 |
| Device Type | 14G Modular |
| Hardware Version | 0.01 |
| Firmware Version | 7.00.00.173 |

This is a Dell PowerEdge (14G) behavior; it is expected on any Dell iDRAC9 that
stages BIOS attribute changes in a pending config job.

### Root cause

The failing task lives in the ci-framework `bm_sno` role:
`roles/bm_sno/tasks/bm_discover_vmedia_target.yml`.

The role does the following in sequence:

1. Sets a one-time boot override via Redfish PATCH on
   `/redfish/v1/Systems/System.Embedded.1`:

   ```yaml
   Boot:
     BootSourceOverrideTarget: UefiTarget
     UefiTargetBootSourceOverride: "{{ cifmw_bm_agent_vmedia_uefi_path }}"
     BootSourceOverrideEnabled: Once
   ```

2. Immediately reads the boot config back and asserts:

   ```yaml
   - _boot_verify.json.Boot.UefiTargetBootSourceOverride | default('') | length > 0
   ```

On Dell iDRAC9, setting `UefiTargetBootSourceOverride` does **not** apply
immediately. It is staged in a **pending BIOS configuration job** that only
commits when the host powers on and runs POST. Therefore an immediate read-back
returns `UefiTargetBootSourceOverride: null` — the value is held in the
scheduled job, not in the live config yet.

Live Redfish state on the node confirms this: the host shows a scheduled BIOS
config job (e.g. `Configure: BIOS.Setup.1-1`, `JobState: Scheduled`) while
`UefiTargetBootSourceOverride` reads `null`.

There are two distinct problems in the assert:

1. **Wrong for Dell hardware (real cause).** The read-back requires
   `UefiTargetBootSourceOverride` to be non-empty, but Dell legitimately reports
   it `null` while the BIOS job is pending. The override *did* apply — it is
   scheduled — so the assertion is checking the wrong condition for this
   hardware.

2. **Jinja bug (cosmetic).** `default('')` in Jinja only substitutes *undefined*
   values; it does **not** replace `None`. So `None | default('') | length` is
   evaluated and throws `NoneType has no len()` instead of failing cleanly. The
   correct idiom would be `default('', true)`.

### Important: providing `SNO_VMEDIA_UEFI_PATH` does not avoid this

Setting `SNO_VMEDIA_UEFI_PATH` (i.e. `cifmw_bm_agent_vmedia_uefi_path`) only
skips the *auto-discovery* block of the task. The PATCH + read-back + assert
steps run regardless of whether the path was supplied or discovered — so the
crash happens either way. The task file does two jobs; only the discovery half is
skipped by supplying the path.

| Stage in `bm_discover_vmedia_target.yml` | Skipped when path is set? |
|---|---|
| Validate provided path is in boot options | no (validates) |
| Auto-discover the path (`when: length == 0`) | **yes** |
| Clear pending jobs + set one-time boot override | no |
| Read back + **assert override applied** ← crashes | **no** |
| Verify VirtualMedia still inserted | no |

Using auto-discovery instead of a static path lands on the identical failure:
discovery finds the same "Virtual Optical Drive" path, PATCHes it, reads back
`null`, and crashes the same way.

### Workaround

At the point of failure the node is already staged and ready: the agent ISO is
inserted as VirtualMedia CD, and the boot config shows
`BootSourceOverrideEnabled: Once`, `BootSourceOverrideMode: UEFI`,
`BootSourceOverrideTarget: UefiTarget`, with the BIOS config job scheduled.

**Power on the node.** Since the override is staged and the ISO is inserted,
powering the host on lets the pending BIOS job commit at POST and the node boots
the agent ISO. Via Redfish:

```bash
curl -sk -u "$USER:$PASS" -X POST \
  https://$BMC/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset \
  -H 'Content-Type: application/json' \
  -d '{"ResetType":"On"}'
```

### Upstream

This is a bug in the ci-framework `bm_sno` role, not a configuration problem.
Worth reporting upstream:

- Dell iDRAC pending-job handling: don't require `UefiTargetBootSourceOverride`
  to be present on immediate read-back when a BIOS config job is scheduled.
- Jinja `default('')`-on-`None`: use `default('', true)`.
