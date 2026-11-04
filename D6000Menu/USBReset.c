#include "USBReset.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>

int32_t d6000_usb_reenumerate(uint64_t registryEntryID) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryEntryID));
    if (service == IO_OBJECT_NULL) {
        return kIOReturnNotFound;
    }

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    IOReturn result = IOCreatePlugInInterfaceForService(service,
                                                        kIOUSBDeviceUserClientTypeID,
                                                        kIOCFPlugInInterfaceID,
                                                        &plugin,
                                                        &score);
    IOObjectRelease(service);
    if (result != kIOReturnSuccess) {
        return result;
    }
    if (plugin == NULL) {
        return kIOReturnNoDevice;
    }

    IOUSBDeviceInterface245 **device = NULL;
    HRESULT queried = (*plugin)->QueryInterface(plugin,
                                                CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID245),
                                                (LPVOID *)&device);
    (*plugin)->Release(plugin);
    if (queried != S_OK || device == NULL) {
        return kIOReturnUnsupported;
    }

    result = (*device)->USBDeviceOpenSeize(device);
    if (result == kIOReturnSuccess) {
        result = (*device)->USBDeviceReEnumerate(device, 0);
        (*device)->USBDeviceClose(device);
    }
    (*device)->Release(device);
    return result;
}
