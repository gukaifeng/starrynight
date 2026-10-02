// Linked only by generate_host.py --native-ui-fixture. This isolated simulator
// app exercises production native pages; it cannot validate Unity rendering.
#import "../../ios/CharacterHost/Bridge/UnityRuntimeBridge.h"

@implementation UnityRuntimeBridge {
    BOOL _started;
}
- (BOOL)started { return _started; }
- (void)startInScene:(UIWindowScene *)scene { _started=YES; }
- (void)showInScene:(UIWindowScene *)scene {}
- (void)setPaused:(BOOL)paused {}
- (void)send:(NSString *)json {}
- (UIViewController *)rootController { return nil; }
@end
