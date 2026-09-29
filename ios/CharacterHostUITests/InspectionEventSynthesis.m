// Test runner only. Xcode's event synthesizer injects real multitouch events into
// the simulator; it does not call the app bridge or bypass UIKit hit testing.
#import "InspectionEventSynthesis.h"
#import <XCTest/XCTest.h>
@interface SNPointerPath : NSObject
- (id)initForTouchAtPoint:(CGPoint)point offset:(double)offset;
- (void)moveToPoint:(CGPoint)point atOffset:(double)offset;
- (void)liftUpAtOffset:(double)offset;
@end
@interface SNEventRecord : NSObject
- (id)initWithName:(NSString *)name interfaceOrientation:(NSInteger)orientation;
- (void)addPointerEventPath:(id)path;
@end
@interface NSObject (SNEventSynthesizer)
- (void)synthesizeEvent:(id)event completion:(void (^)(BOOL, NSError *))completion;
@end
void SNSynthesizeInspection(CGPoint start, CGSize viewport, void (^completion)(NSError *)) {
    Class pathClass=NSClassFromString(@"XCPointerEventPath"), recordClass=NSClassFromString(@"XCSynthesizedEventRecord");
    id device=[XCUIDevice sharedDevice];
    SEL selector=NSSelectorFromString(@"eventSynthesizer");
    if(!pathClass || !recordClass || ![device respondsToSelector:selector]) {
        completion([NSError errorWithDomain:@"InspectionTest" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Xcode event synthesis unavailable"}]);return;
    }
    id synth=[device valueForKey:@"eventSynthesizer"];
    SNEventRecord *record=[[recordClass alloc] initWithName:@"held-character-two-finger-inspection" interfaceOrientation:1];
    SNPointerPath *one=[[pathClass alloc] initForTouchAtPoint:start offset:0];
    [one moveToPoint:start atOffset:1.5];
    CGPoint second=CGPointMake(start.x+70,start.y+5);
    SNPointerPath *two=[[pathClass alloc] initForTouchAtPoint:second offset:1.65];
    CGPoint firstEnd=CGPointMake(start.x+10,start.y+viewport.height*.12);
    CGPoint secondEnd=CGPointMake(second.x+55,second.y+viewport.height*.12);
    [one moveToPoint:firstEnd atOffset:2.5]; [two moveToPoint:secondEnd atOffset:2.5];
    [one moveToPoint:firstEnd atOffset:5]; [two moveToPoint:secondEnd atOffset:5];
    [two liftUpAtOffset:5.1];
    [one moveToPoint:CGPointMake(firstEnd.x+22,firstEnd.y) atOffset:5.5];
    [one liftUpAtOffset:5.9];
    [record addPointerEventPath:one];[record addPointerEventPath:two];
    [synth synthesizeEvent:record completion:^(BOOL success, NSError *error) { dispatch_async(dispatch_get_main_queue(), ^{ completion(error); }); }];
}

void SNSynthesizeViewEdit(CGPoint start, CGSize viewport, void (^completion)(NSError *)) {
    Class paths=NSClassFromString(@"XCPointerEventPath"),records=NSClassFromString(@"XCSynthesizedEventRecord");
    id device=[XCUIDevice sharedDevice];
    if(!paths || !records || ![device respondsToSelector:NSSelectorFromString(@"eventSynthesizer")]) {
        completion([NSError errorWithDomain:@"ViewEditTest" code:1 userInfo:nil]);return;
    }
    id record=[[records alloc] initWithName:@"edit-character-two-finger" interfaceOrientation:1];
    id one=[[paths alloc] initForTouchAtPoint:start offset:0];
    CGPoint second=CGPointMake(start.x+65,start.y);
    id two=[[paths alloc] initForTouchAtPoint:second offset:.18];
    CGPoint end=CGPointMake(start.x-8,start.y+viewport.height*.05);
    CGPoint endTwo=CGPointMake(second.x+22,second.y+viewport.height*.05);
    [one moveToPoint:end atOffset:.95];[two moveToPoint:endTwo atOffset:.95];
    [one moveToPoint:end atOffset:2];[two moveToPoint:endTwo atOffset:2];
    [two liftUpAtOffset:2.15];[one liftUpAtOffset:2.35];
    [record addPointerEventPath:one];[record addPointerEventPath:two];
    [[device valueForKey:@"eventSynthesizer"] synthesizeEvent:record completion:^(BOOL success,NSError *error) {
        dispatch_async(dispatch_get_main_queue(),^{completion(error);});
    }];
}
