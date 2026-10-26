/*
 * Surface Go 3 battery for macOS.
 *
 * The Go 3 firmware names its battery \_SB.BAT1 with _HID "MSHW0146" instead of the
 * standard PNP0C0A (the Go 2 uses PNP0C0A), so VirtualSMC's SMCBatteryManager, which
 * looks for PNP0C0A, never finds it. The battery methods themselves (_BIX/_BST reading
 * EC0 fields) are standard and are handled by SMCBatteryManager + ECEnabler.
 *
 * Pair with the config.plist ACPI patch that renames that _HID to XHID in the DSDT
 * (find 5F4849440D4D5348573031343600, replace 584849440D4D5348573031343600).
 */
DefinitionBlock ("", "SSDT", 2, "SGO3", "BAT1FIX", 0x00001000)
{
    External (_SB_.BAT1, DeviceObj)

    Scope (\_SB.BAT1)
    {
        // Only when the rename patch applied, so there is never a second _HID.
        If (CondRefOf (\_SB.BAT1.XHID))
        {
            Name (_HID, EisaId ("PNP0C0A") /* Control Method Battery */)
        }
        Else
        {
            // Rename did not apply (e.g. after a firmware update): fall back to a compatible ID.
            Name (_CID, EisaId ("PNP0C0A") /* Control Method Battery */)
        }
    }
}
