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
    // Event paths interpolate between samples. Hold both fingers still before
    // moving; otherwise finger one can cross the pan threshold before .18s.
    [one moveToPoint:start atOffset:.30];[two moveToPoint:second atOffset:.30];
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

void SNSynthesizeConversationTurn(CGPoint start, CGPoint bend, CGPoint end, void (^completion)(NSError *)) {
    Class paths=NSClassFromString(@"XCPointerEventPath"),records=NSClassFromString(@"XCSynthesizedEventRecord");
    id device=[XCUIDevice sharedDevice];
    if(!paths || !records || ![device respondsToSelector:NSSelectorFromString(@"eventSynthesizer")]) {
        completion([NSError errorWithDomain:@"ConversationGestureTest" code:1 userInfo:nil]);return;
    }
    id record=[[records alloc] initWithName:@"conversation-direction-lock" interfaceOrientation:1];
    id one=[[paths alloc] initForTouchAtPoint:start offset:0];
    [one moveToPoint:start atOffset:.06];[one moveToPoint:bend atOffset:.38];
    [one moveToPoint:end atOffset:.9];[one liftUpAtOffset:1.05];
    [record addPointerEventPath:one];
    [[device valueForKey:@"eventSynthesizer"] synthesizeEvent:record completion:^(BOOL success,NSError *error) {
        dispatch_async(dispatch_get_main_queue(),^{completion(error ?: (success ? nil : [NSError errorWithDomain:@"ConversationGestureTest" code:2 userInfo:nil]));});
    }];
}

void SNSynthesizeConversationShake(CGPoint start, void (^completion)(NSError *)) {
    Class paths=NSClassFromString(@"XCPointerEventPath"),records=NSClassFromString(@"XCSynthesizedEventRecord");
    id device=[XCUIDevice sharedDevice];
    if(!paths || !records || ![device respondsToSelector:NSSelectorFromString(@"eventSynthesizer")]) {
        completion([NSError errorWithDomain:@"ConversationShakeTest" code:1 userInfo:nil]);return;
    }
    id record=[[records alloc] initWithName:@"conversation-repeated-small-rotation" interfaceOrientation:1];
    id one=[[paths alloc] initForTouchAtPoint:start offset:0];
    [one moveToPoint:start atOffset:.06];
    for(int i=0;i<8;i++)[one moveToPoint:CGPointMake(start.x+(i%2==0?100:-100),start.y) atOffset:.32+i*.32];
    [one liftUpAtOffset:2.75];[record addPointerEventPath:one];
    [[device valueForKey:@"eventSynthesizer"] synthesizeEvent:record completion:^(BOOL success,NSError *error) {
        dispatch_async(dispatch_get_main_queue(),^{completion(error ?: (success ? nil : [NSError errorWithDomain:@"ConversationShakeTest" code:2 userInfo:nil]));});
    }];
}

void SNSynthesizePreviewCancellation(CGPoint start, CGSize viewport, void (^completion)(NSError *)) {
    Class paths=NSClassFromString(@"XCPointerEventPath"),records=NSClassFromString(@"XCSynthesizedEventRecord");
    id device=[XCUIDevice sharedDevice];
    if(!paths || !records || ![device respondsToSelector:NSSelectorFromString(@"eventSynthesizer")]) {
        completion([NSError errorWithDomain:@"PreviewRotationTest" code:1 userInfo:nil]);return;
    }
    id record=[[records alloc] initWithName:@"cancel-temporary-turn-with-second-finger" interfaceOrientation:1];
    id one=[[paths alloc] initForTouchAtPoint:start offset:0];
    CGPoint turn=CGPointMake(start.x+viewport.width*.1,start.y+20);
    [one moveToPoint:turn atOffset:.45];
    CGPoint second=CGPointMake(turn.x+45,turn.y);
    id two=[[paths alloc] initForTouchAtPoint:second offset:.65];
    CGPoint end=CGPointMake(turn.x-10,turn.y+50),endTwo=CGPointMake(second.x+20,second.y+50);
    [one moveToPoint:end atOffset:1.2];[two moveToPoint:endTwo atOffset:1.2];
    [two liftUpAtOffset:1.35];
    [one moveToPoint:CGPointMake(end.x-50,end.y) atOffset:1.8];[one liftUpAtOffset:2.1];
    [record addPointerEventPath:one];[record addPointerEventPath:two];
    [[device valueForKey:@"eventSynthesizer"] synthesizeEvent:record completion:^(BOOL success,NSError *error) {
        dispatch_async(dispatch_get_main_queue(),^{completion(error ?: (success ? nil : [NSError errorWithDomain:@"PreviewRotationTest" code:2 userInfo:nil]));});
    }];
}
