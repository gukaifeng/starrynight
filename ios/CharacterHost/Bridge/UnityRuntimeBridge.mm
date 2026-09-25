#import "UnityRuntimeBridge.h"
#import <UnityFramework/UnityFramework.h>
#include <vector>
#include <string>

extern "C" void MSRegisterEventCallback(void (*callback)(const char *));
static __weak UnityRuntimeBridge *activeBridge;
static void ReceiveUnityEvent(const char *json)
{
    NSString *copy = json ? [[NSString alloc] initWithUTF8String:json] : nil;
    if (!copy) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UnityRuntimeBridge *bridge = activeBridge;
        [bridge.delegate runtimeDidReceive:copy];
    });
}

@implementation UnityRuntimeBridge {
    UnityFramework *_framework;
    BOOL _started;
}
- (BOOL)started { return _started; }
- (void)startInScene:(UIWindowScene *)scene
{
    NSAssert([NSThread isMainThread], @"Unity must start on the main thread");
    if (_started) return;
    _started = YES;
    activeBridge = self;
    _framework = [UnityFramework getInstance];
    [_framework setExecuteHeader:&_mh_execute_header];
    NSString *identifier = [NSBundle bundleForClass:[UnityFramework class]].bundleIdentifier;
    [_framework setDataBundleId:identifier.UTF8String];
    MSRegisterEventCallback(ReceiveUnityEvent);
    static std::vector<std::string> arguments;
    static std::vector<char *> argv;
    for (NSString *arg in NSProcessInfo.processInfo.arguments) arguments.emplace_back(arg.UTF8String);
    for (auto &arg : arguments) argv.push_back(arg.data());
    argv.push_back(nullptr);
    [_framework runEmbeddedWithArgc:(int)arguments.size() argv:argv.data() appLaunchOpts:nil];
    _framework.appController.window.windowScene = scene;
}
- (void)showInScene:(UIWindowScene *)scene
{
    _framework.appController.window.windowScene = scene;
    [_framework showUnityWindow];
}
- (void)setPaused:(BOOL)paused { if (_started) [_framework pause:paused]; }
- (void)send:(NSString *)json
{
    if (_started) [_framework sendMessageToGOWithName:"AppBridgeReceiver" functionName:"ReceiveCommand" message:json.UTF8String];
}
- (UIViewController *)rootController { return _framework.appController.rootViewController; }
@end
