#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
void SNSynthesizeInspection(CGPoint start, CGSize viewport, void (^ _Nonnull completion)(NSError * _Nullable));
void SNSynthesizeViewEdit(CGPoint start, CGSize viewport, void (^ _Nonnull completion)(NSError * _Nullable));
void SNSynthesizePreviewCancellation(CGPoint start, CGSize viewport, void (^ _Nonnull completion)(NSError * _Nullable));
void SNSynthesizeConversationTurn(CGPoint start, CGPoint bend, CGPoint end, void (^ _Nonnull completion)(NSError * _Nullable));
