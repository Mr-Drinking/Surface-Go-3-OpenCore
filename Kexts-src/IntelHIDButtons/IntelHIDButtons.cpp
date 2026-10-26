/*
 * IntelHIDButtons: tablet buttons reported through the Intel HID event filter device
 * (INT33D5), such as the Surface Go 3 volume buttons.
 *
 * Copyright (c) 2026 Mr-Drinking. SPDX-License-Identifier: MIT
 * The virtual keyboard follows acidanthera/BrightnessKeys (BSD-3-Clause).
 */

#include "IntelHIDButtons.hpp"

#include <IOKit/IOLib.h>
#include <IOKit/acpi/IOACPITypes.h>
#include <IOKit/hidsystem/ev_keymap.h>

#define super IOHIKeyboard
OSDefineMetaClassAndStructors(IntelHIDButtons, IOHIKeyboard);

#define LOG(fmt, ...) IOLog("IntelHIDButtons: " fmt "\n", ##__VA_ARGS__)

// Intel HID event filter _DSM UUID eeec56b3-4442-408f-a792-4edd4d758054, in ACPI byte order.
static const UInt8 kHIDDSMUUID[16] = {
    0xb3, 0x56, 0xec, 0xee, 0x42, 0x44, 0x8f, 0x40,
    0xa7, 0x92, 0x4e, 0xdd, 0x4d, 0x75, 0x80, 0x54,
};

// _DSM function indices, and the method each one maps to when there is no _DSM.
enum : UInt32 {
    kFnBTNL = 1,  // a buttons driver is loaded
    kFnHDMM = 2,  // HID mode, 0 is the simple mode
    kFnHDSM = 3,  // HID driver ready
    kFnBTNE = 6,  // enable the button array
};
static const char *const kFnMethods[] = {nullptr, "BTNL", "HDMM", "HDSM", "HDEM", "BTNS", "BTNE"};

// Notifications sent to the device by the 5 button array.
enum : UInt32 {
    kEvVolumeUpPress    = 0xc4,
    kEvVolumeUpRelease  = 0xc5,
    kEvVolumeDownPress  = 0xc6,
    kEvVolumeDownRelease = 0xc7,
    kEvPowerPress       = 0xce,
    kEvPowerRelease     = 0xcf,
};

// ADB codes the keymap below declares as special keys (same as VoodooPS2).
enum : UInt8 {
    kADBVolumeUp   = 0x48,
    kADBVolumeDown = 0x49,
    kADBMute       = 0x4a,
    kADBPower      = 0x7f,
};

static IOPMPowerState gPowerStates[] = {
    {kIOPMPowerStateVersion1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {kIOPMPowerStateVersion1, kIOPMPowerOn, kIOPMPowerOn, kIOPMPowerOn, 0, 0, 0, 0, 0, 0, 0, 0},
};

IOReturn IntelHIDButtons::evaluateDSM(UInt32 fn, OSObject *arg, OSObject **result) {
    OSData *uuid = OSData::withBytes(kHIDDSMUUID, sizeof(kHIDDSMUUID));
    OSNumber *revision = OSNumber::withNumber(1ULL, 32);
    OSNumber *index = OSNumber::withNumber(fn, 32);
    OSArray *package = OSArray::withCapacity(1);
    IOReturn status = kIOReturnNoMemory;

    if (uuid && revision && index && package) {
        if (arg)
            package->setObject(arg);
        OSObject *params[] = {uuid, revision, index, package};
        status = hidd->evaluateObject("_DSM", result, params, 4);
    }

    OSSafeReleaseNULL(uuid);
    OSSafeReleaseNULL(revision);
    OSSafeReleaseNULL(index);
    OSSafeReleaseNULL(package);
    return status;
}

IOReturn IntelHIDButtons::callHID(UInt32 fn, UInt64 *result, bool hasArg, UInt64 arg) {
    OSNumber *argument = hasArg ? OSNumber::withNumber(arg, 64) : nullptr;
    if (hasArg && !argument)
        return kIOReturnNoMemory;

    OSObject *ret = nullptr;
    IOReturn status;
    if (dsmMask & (1U << fn)) {
        status = evaluateDSM(fn, argument, &ret);
    } else {
        OSObject *params[] = {argument};
        status = hidd->evaluateObject(kFnMethods[fn], &ret, hasArg ? params : nullptr, hasArg ? 1 : 0);
    }

    if (status == kIOReturnSuccess && result) {
        OSNumber *number = OSDynamicCast(OSNumber, ret);
        if (number)
            *result = number->unsigned64BitValue();
        else
            status = kIOReturnBadArgument;
    }

    OSSafeReleaseNULL(ret);
    OSSafeReleaseNULL(argument);
    return status;
}

void IntelHIDButtons::readDSMMask() {
    if (hidd->validateObject("_DSM") != kIOReturnSuccess)
        return;

    // Function 0 returns a bit mask of the implemented functions; bit 0 says the mask is valid.
    OSObject *ret = nullptr;
    if (evaluateDSM(0, nullptr, &ret) == kIOReturnSuccess) {
        OSData *data = OSDynamicCast(OSData, ret);
        if (data) {
            const UInt8 *bytes = static_cast<const UInt8 *>(data->getBytesNoCopy());
            for (unsigned i = 0; i < data->getLength() && i < sizeof(dsmMask); i++)
                dsmMask |= static_cast<UInt32>(bytes[i]) << (8 * i);
        }
    }
    OSSafeReleaseNULL(ret);

    if (!(dsmMask & 1))
        dsmMask = 0;
}

void IntelHIDButtons::enableButtons() {
    // Report a buttons driver as loaded. On the Surface Go 3 this makes the EC send the buttons
    // here (EC0.HFON = 1) and hides the ACPI power button, so the power button is posted too.
    if (callHID(kFnBTNL) != kIOReturnSuccess)
        LOG("BTNL failed");

    UInt64 mode = 0;
    if (callHID(kFnHDMM, &mode) == kIOReturnSuccess && mode != 0)
        LOG("HID mode %llu is not the simple mode, buttons may not work", mode);

    if (callHID(kFnHDSM, nullptr, true, 1) != kIOReturnSuccess)
        LOG("HDSM failed");

    if (buttonCaps && callHID(kFnBTNE, nullptr, true, buttonCaps) != kIOReturnSuccess)
        LOG("BTNE failed");
}

void IntelHIDButtons::postKey(UInt8 adbCode, bool goingDown) {
    uint64_t now;
    clock_get_uptime(&now);
    dispatchKeyboardEvent(adbCode, goingDown, *reinterpret_cast<AbsoluteTime *>(&now));
}

bool IntelHIDButtons::start(IOService *provider) {
    hidd = OSDynamicCast(IOACPIPlatformDevice, provider);
    if (!hidd)
        return false;

    readDSMMask();
    UInt32 caps = 0;
    if (hidd->evaluateInteger("BTNC", &caps) == kIOReturnSuccess)
        buttonCaps = caps;

    if (!super::start(provider))
        return false;
    ready = true;

    enableButtons();

    // Enable again after wake: the firmware may reset the EC while the system sleeps.
    PMinit();
    provider->joinPMtree(this);
    registerPowerDriver(this, gPowerStates, 2);

    setProperty("DSMFunctions", dsmMask, 32);
    setProperty("ButtonCaps", buttonCaps, 32);
    LOG("started, _DSM functions 0x%x, button caps 0x%x", dsmMask, buttonCaps);
    return true;
}

void IntelHIDButtons::stop(IOService *provider) {
    ready = false;
    PMstop();
    super::stop(provider);
}

IOReturn IntelHIDButtons::message(UInt32 type, IOService *provider, void *argument) {
    if (type != kIOACPIMessageDeviceNotification || provider != hidd || !argument)
        return super::message(type, provider, argument);
    if (!ready)
        return kIOReturnSuccess;

    UInt32 event = *static_cast<UInt32 *>(argument);
    switch (event) {
        case kEvVolumeUpPress:     postKey(kADBVolumeUp, true); break;
        case kEvVolumeUpRelease:   postKey(kADBVolumeUp, false); break;
        case kEvVolumeDownPress:   postKey(kADBVolumeDown, true); break;
        case kEvVolumeDownRelease: postKey(kADBVolumeDown, false); break;
        // The Mac power key with the real press duration: macOS then applies its usual power
        // button behavior (hold to sleep, Control-Power for the shut down dialog, ...).
        case kEvPowerPress:        postKey(kADBPower, true); break;
        case kEvPowerRelease:      postKey(kADBPower, false); break;
        default:
            LOG("ignored event 0x%x", event);
            break;
    }
    return kIOReturnSuccess;
}

IOReturn IntelHIDButtons::setPowerState(unsigned long powerStateOrdinal, IOService *whatDevice) {
    if (powerStateOrdinal == 1 && ready)
        enableButtons();
    return kIOPMAckImplied;
}

UInt32 IntelHIDButtons::deviceType() { return 3; }

UInt32 IntelHIDButtons::interfaceID() { return NX_EVS_DEVICE_INTERFACE_ADB; }

UInt32 IntelHIDButtons::maxKeyCodes() { return NX_NUMKEYCODES; }

const unsigned char *IntelHIDButtons::defaultKeymapOfLength(UInt32 *length) {
    // Keymap format from IOHIDFamily's IOHIKeyboardMapper: no modifiers, no character keys,
    // no sequences, only the special volume and power keys.
    static const unsigned char keymap[] = {
        0x00, 0x00,  // byte-sized entries
        0x00,        // modifier keys
        0x00,        // key definitions
        0x00,        // key sequences
        0x04,        // special keys: (NX_KEYTYPE, ADB code)
        NX_KEYTYPE_SOUND_UP,   kADBVolumeUp,
        NX_KEYTYPE_SOUND_DOWN, kADBVolumeDown,
        NX_KEYTYPE_MUTE,       kADBMute,
        NX_POWER_KEY,          kADBPower,
    };
    *length = sizeof(keymap);
    return keymap;
}
