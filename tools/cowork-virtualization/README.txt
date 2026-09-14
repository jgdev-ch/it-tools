============================================================
 CLAUDE COWORK VIRTUALIZATION SETUP - TECH REFERENCE
============================================================

PURPOSE
-------
Prepares a single user's machine to run Claude Cowork. Cowork
runs its code-execution sandbox inside a lightweight VM built
on the Windows Host Compute Service, which needs the Virtual
Machine Platform feature enabled and hardware virtualization
switched on in firmware.

This is a spot fix you drop on a machine, run once, and then
remove. It is not a fleet deployment. Nothing is installed and
nothing phones home.

Safe to re-run. If everything is already in place it reports
that and changes nothing.

WHEN TO USE
-----------
- A user has an approved Cowork use case and needs it enabled
- Claude Desktop reports "Virtualization is not enabled"
- Cowork sessions fail to start on an otherwise healthy machine

WHEN NOT TO USE
---------------
- Windows Home edition. Cowork needs the fuller Hyper-V and HCS
  stack that Home does not ship. The script fails fast on this
  rather than reporting a machine ready that never will be.
- Virtual desktops or VMs without nested virtualization enabled
  by the host. Anthropic does not support Cowork on these.
- The user has not been approved for Cowork yet.

PREREQUISITES
-------------
Windows 11 Pro, Enterprise, or Education (or Windows 10 22H2
and later). Local administrator rights on the target machine.

No PowerShell modules to install. The script uses only
in-box Windows cmdlets.

USAGE
-----
Extract the whole zip to the user's machine, then double-click
Run-EnableCoworkVirtualization.bat

It self-elevates, so accept the UAC prompt. Keep both files
together in the same folder.

You will be asked to confirm before the boot configuration is
changed. Nothing else prompts.

WHAT THE SCRIPT DOES
--------------------
Phase 1 - Checks the host: administrator rights, Windows
          edition and build, CPU architecture, whether this is
          a physical machine, and whether Claude Desktop is
          installed for the signed-in user
Phase 2 - Checks that hardware virtualization is enabled in
          firmware. It cannot change BIOS/UEFI settings, so if
          this is off you get told to go do it by hand
Phase 3 - Checks the Virtual Machine Platform feature and
          enables it if it is off
Phase 4 - Checks the hypervisor launch type in the boot
          configuration. If it has been set to off, which is a
          common leftover from gaming or anti-cheat fixes, it
          offers to set it back to Auto
Phase 5 - Checks the Host Compute Service components
          (vmcompute, hns, vfpext) and Cowork's own service
Phase 6 - Reports whether the machine is ready or needs a
          restart

AFTER THE SCRIPT
----------------
Step 1: If it asked for a restart, restart the machine. Cowork
        will keep reporting that virtualization is unavailable
        until that happens. There is no way around it.
Step 2: Launch Claude Desktop and confirm Cowork starts.
Step 3: Copy the log file out of the folder and attach it to
        the ticket.
Step 4: Delete the extracted folder from the user's machine.

LOG FILE
--------
Every run writes CoworkVirtualization-<timestamp>.log next to
the script, in whatever folder you extracted it to. It holds
the full console output, including which checks passed and
whether you confirmed the boot configuration change.

If the folder is not writable the log goes to %TEMP% instead
and the script tells you so.

EXIT CODES
----------
The launcher prints these in plain English, but the raw codes
are here in case this ever gets packaged for Intune.

0     Ready. No restart needed.
3010  Success, restart required. Standard Intune soft-reboot
      code, so a future Intune package gets correct reboot
      handling for free.
1     Not running as administrator.
2     Enabling Virtual Machine Platform failed.
3     Host not supported (edition, build, architecture, or
      firmware virtualization is off).
4     Virtualization is fine but Claude Desktop's components
      are missing. Reinstall Claude Desktop.

NOTES
-----
The launcher calls powershell.exe (5.1) rather than pwsh.exe,
which is the opposite of the other hub scripts. This is on
purpose: the DISM cmdlets in Phase 3 are 5.1-native and go
through a compatibility shim under PowerShell 7. Do not
change it.

============================================================
