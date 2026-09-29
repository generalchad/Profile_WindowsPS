New Scan Share
==============

Sets up this PC to receive scans from an office copier/printer (MFP) and saves
them into a folder. It creates the folder, a locked-down account the copier logs
in with, the network share, and the firewall rule - then shows you the exact
values to type into the copier's address book.

Requirements
------------
* Windows 10, Windows 11, or Windows Server 2016 or newer (64-bit).
* Already installed on any Windows PC that has PowerShell.
* Administrator rights are needed to actually create the share. Windows will ask
  (UAC) when you click Create.


How to install (one time)
-------------------------
1. Copy this whole folder onto the PC (for example to your Desktop). If you got
   it as a .zip, right-click the .zip > Properties > Unblock, then extract it.
2. Double-click:  Install-ScanShare.cmd
3. A "New Scan Share" icon appears on the Desktop.

That's it. The installer only sets things up for you (your Windows account); it
does not need administrator rights.


How to use
----------
1. Double-click the "New Scan Share" icon on the Desktop.
2. Fill in the fields (the defaults are usually fine). Click Preview to see what
   would happen, then Create to apply it.
3. When Windows asks for administrator permission, click Yes.
4. When it finishes, click "Copy settings" and type those values into the copier's
   address book.


Updating
--------
Run Install-ScanShare.cmd again from a newer copy of this folder. It replaces the
old version and leaves your existing scan share in place.


Uninstalling
------------
Double-click:  Uninstall-ScanShare.cmd

This removes the tool and its Desktop icon only. Any scan share, folder, or
account it created earlier is left as-is.


Sharing with other PCs
----------------------
This same folder is all you need. Copy it to a network share or send it on, and
each person double-clicks Install-ScanShare.cmd on their own PC.
