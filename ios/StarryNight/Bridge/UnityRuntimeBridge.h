#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@protocol UnityRuntimeBridgeDelegate <NSObject>
- (void)runtimeDidReceive:(NSString *)json;
@end

@interface UnityRuntimeBridge : NSObject
@property(nonatomic, weak, nullable) id<UnityRuntimeBridgeDelegate> delegate;
@property(nonatomic, readonly) BOOL started;
- (void)startInScene:(UIWindowScene *)scene NS_SWIFT_NAME(start(in:));
- (void)showInScene:(UIWindowScene *)scene NS_SWIFT_NAME(show(in:));
- (void)setPaused:(BOOL)paused;
- (void)send:(NSString *)json;
- (nullable UIViewController *)rootController;
@end
NS_ASSUME_NONNULL_END
