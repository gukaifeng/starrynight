#import <Foundation/Foundation.h>

typedef void (*ModelSpaceCallback)(const char *);
static ModelSpaceCallback callback = nullptr;

extern "C" __attribute__((visibility("default")))
void MSRegisterEventCallback(ModelSpaceCallback value) { callback = value; }

extern "C" __attribute__((visibility("default")))
void MSNativeSendEvent(const char *json) { if (callback && json) callback(json); }
