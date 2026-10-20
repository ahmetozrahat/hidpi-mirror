// Private IOKit interfaces for I2C access to external displays on Apple Silicon,
// used to send DDC/CI commands. Same declarations as MonitorControl and m1ddc.

#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/IOKitLib.h>

CF_ASSUME_NONNULL_BEGIN

typedef CFTypeRef IOAVServiceRef;

extern IOAVServiceRef _Nullable IOAVServiceCreateWithService(CFAllocatorRef _Nullable allocator, io_service_t service)
    CF_RETURNS_RETAINED;
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t offset, void *outputBuffer,
                                   uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t dataAddress, void *inputBuffer,
                                    uint32_t inputBufferSize);

CF_ASSUME_NONNULL_END
