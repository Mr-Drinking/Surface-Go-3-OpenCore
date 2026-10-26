/*
 * IntelHIDButtons: tablet buttons reported through the Intel HID event filter device
 * (INT33D5), such as the Surface Go 3 volume buttons.
 *
 * Copyright (c) 2026 Mr-Drinking. SPDX-License-Identifier: MIT
 * The virtual keyboard follows acidanthera/BrightnessKeys (BSD-3-Clause).
 */

#ifndef IntelHIDButtons_hpp
#define IntelHIDButtons_hpp

#include <IOKit/IOService.h>
#include <IOKit/hidsystem/IOHIKeyboard.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>

class IntelHIDButtons : public IOHIKeyboard {
    OSDeclareDefaultStructors(IntelHIDButtons)

    IOACPIPlatformDevice *hidd {nullptr};
    UInt32 dsmMask {0};     // functions implemented by _DSM; 0 means call the methods directly
    UInt32 buttonCaps {0};  // BTNE argument from BTNC; 0 means the device has no button array
    bool ready {false};     // the keymap exists, so key events can be dispatched

    IOReturn evaluateDSM(UInt32 fn, OSObject *arg, OSObject **result);
    IOReturn callHID(UInt32 fn, UInt64 *result = nullptr, bool hasArg = false, UInt64 arg = 0);
    void readDSMMask();
    void enableButtons();
    void postKey(UInt8 adbCode, bool goingDown);

public:
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    IOReturn message(UInt32 type, IOService *provider, void *argument = nullptr) override;
    IOReturn setPowerState(unsigned long powerStateOrdinal, IOService *whatDevice) override;

    UInt32 deviceType() override;
    UInt32 interfaceID() override;
    UInt32 maxKeyCodes() override;
    const unsigned char *defaultKeymapOfLength(UInt32 *length) override;
};

#endif
