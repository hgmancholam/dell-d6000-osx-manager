#pragma once

#include <stdint.h>

// Returns a kern_return_t / IOReturn; 0 means the re-enumeration request was accepted.
int32_t d6000_usb_reenumerate(uint64_t registryEntryID);
