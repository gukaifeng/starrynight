#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
void SNSynthesizeInspection(CGPoint start, CGSize viewport, void (^ _Nonnull completion)(NSError * _Nullable));
void SNSynthesizeViewEdit(CGPoint start, CGSize viewport, void (^ _Nonnull completion)(NSError * _Nullable));
void SNSynthesizePreviewCancellation(CGPoint start, CGSize viewport, void (^ _Nonnull completion)(NSError * _Nullable));
void SNSynthesizeConversationTurn(CGPoint start, CGPoint bend, CGPoint end, void (^ _Nonnull completion)(NSError * _Nullable));
void SNSynthesizeConversationShake(CGPoint start, void (^ _Nonnull completion)(NSError * _Nullable));
void SNSynthesizePreviewPinch(CGPoint center, CGFloat ratio, void (^ _Nonnull completion)(NSError * _Nullable));
