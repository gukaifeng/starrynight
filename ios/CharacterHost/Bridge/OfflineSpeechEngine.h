#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Owns a serial CPU inference queue. No network, audio session, or microphone access.
@interface OfflineSpeechEngine : NSObject
- (instancetype)initWithModelDirectory:(NSString *)directory;
- (void)recognizeWave:(NSData *)wave completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion;
- (void)synthesize:(NSString *)text speed:(double)speed completion:(void (^)(NSData * _Nullable, NSError * _Nullable))completion;
/// Invalidates queued work immediately. In-flight ONNX kernels finish before release.
- (void)cancel;
/// Release models on the inference queue, never concurrently with a decode.
- (void)releaseModels;
@end
NS_ASSUME_NONNULL_END
