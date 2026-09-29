#import "OfflineSpeechEngine.h"
#import <SherpaOnnxC/sherpa-onnx/c-api/c-api.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <memory>

namespace {
NSError *SpeechError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"XiaobanOfflineSpeech" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}
NSError *Cancelled() { return [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]; }
struct Cancellation { std::atomic<uint64_t> *current; uint64_t expected; };
int32_t Progress(const float *, int32_t, float, void *arg) {
    auto *state = static_cast<Cancellation *>(arg);
    return state->current->load() == state->expected ? 1 : 0;
}
NSData *WaveData(const SherpaOnnxGeneratedAudio *audio) {
    // iOS platforms are little-endian; generate canonical mono PCM16 WAV in memory.
    uint32_t bytes = static_cast<uint32_t>(audio->n) * 2;
    NSMutableData *out = [NSMutableData dataWithCapacity:44 + bytes];
    auto u32 = [&](uint32_t v) { [out appendBytes:&v length:4]; };
    auto u16 = [&](uint16_t v) { [out appendBytes:&v length:2]; };
    [out appendBytes:"RIFF" length:4]; u32(36 + bytes); [out appendBytes:"WAVEfmt " length:8];
    u32(16); u16(1); u16(1); u32(audio->sample_rate); u32(audio->sample_rate * 2); u16(2); u16(16);
    [out appendBytes:"data" length:4]; u32(bytes);
    [out increaseLengthBy:bytes];
    auto *samples = reinterpret_cast<int16_t *>(static_cast<uint8_t *>(out.mutableBytes) + 44);
    for (int32_t i = 0; i < audio->n; ++i) {
        float value = std::isfinite(audio->samples[i]) ? audio->samples[i] : 0;
        samples[i] = static_cast<int16_t>(std::lrint(std::clamp(value, -1.0f, 1.0f) * 32767));
    }
    return out;
}
}

@implementation OfflineSpeechEngine {
    NSString *_directory;
    dispatch_queue_t _queue;
    std::atomic<uint64_t> _generation;
    const SherpaOnnxOfflineRecognizer *_recognizer;
    const SherpaOnnxOfflineTts *_tts;
}
- (instancetype)initWithModelDirectory:(NSString *)directory {
    if ((self = [super init])) {
        _directory = [directory copy];
        _queue = dispatch_queue_create("com.xiaoban.offline-speech", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
        _generation = 0; _recognizer = nullptr; _tts = nullptr;
    }
    return self;
}
- (void)dealloc { [self clearModels]; }
- (const char *)path:(NSString *)relative { return [[_directory stringByAppendingPathComponent:relative] fileSystemRepresentation]; }
- (void)clearModels {
    if (_recognizer) { SherpaOnnxDestroyOfflineRecognizer(_recognizer); _recognizer = nullptr; }
    if (_tts) { SherpaOnnxDestroyOfflineTts(_tts); _tts = nullptr; }
}
- (void)cancel { _generation.fetch_add(1); }
- (void)releaseModels {
    [self cancel];
    dispatch_async(_queue, ^{ [self clearModels]; });
}
- (BOOL)loadRecognizer {
    if (_recognizer) return YES;
    [self clearModels]; // Only one speech model remains resident alongside Unity.
    SherpaOnnxOfflineRecognizerConfig config = {};
    config.feat_config.sample_rate = 16000; config.feat_config.feature_dim = 80;
    config.model_config.sense_voice.model = [self path:@"sensevoice/model.int8.onnx"];
    config.model_config.sense_voice.language = "auto"; config.model_config.sense_voice.use_itn = 1;
    config.model_config.tokens = [self path:@"sensevoice/tokens.txt"];
    config.model_config.num_threads = 2; config.model_config.provider = "cpu";
    config.decoding_method = "greedy_search";
    _recognizer = SherpaOnnxCreateOfflineRecognizer(&config);
    return _recognizer != nullptr;
}
- (BOOL)loadSynthesizer {
    if (_tts) return YES;
    [self clearModels];
    SherpaOnnxOfflineTtsConfig config = {};
    config.model.vits.model = [self path:@"melo/model.onnx"];
    config.model.vits.tokens = [self path:@"melo/tokens.txt"];
    config.model.vits.lexicon = [self path:@"melo/lexicon.txt"];
    config.model.vits.dict_dir = [self path:@"melo/dict"];
    config.model.vits.noise_scale = 0.667f; config.model.vits.noise_scale_w = 0.8f; config.model.vits.length_scale = 1;
    config.model.num_threads = 2; config.model.provider = "cpu";
    config.max_num_sentences = 1; config.silence_scale = 0.2f;
    NSString *rules = [@[[NSString stringWithUTF8String:[self path:@"melo/date.fst"]],
                         [NSString stringWithUTF8String:[self path:@"melo/number.fst"]],
                         [NSString stringWithUTF8String:[self path:@"melo/phone.fst"]]] componentsJoinedByString:@","];
    config.rule_fsts = rules.UTF8String;
    _tts = SherpaOnnxCreateOfflineTts(&config);
    return _tts != nullptr;
}
- (void)recognizeWave:(NSData *)wave completion:(void (^)(NSString *, NSError *))completion {
    uint64_t token = _generation.load();
    dispatch_async(_queue, ^{ @autoreleasepool {
        NSString *text = nil; NSError *error = nil;
        try {
            if (token != self->_generation.load()) error = Cancelled();
            else if (wave.length < 44 || wave.length > 4 * 1024 * 1024) error = SpeechError(1, @"录音格式不正确或文件过大。");
            else {
                auto audio = std::unique_ptr<const SherpaOnnxWave, decltype(&SherpaOnnxFreeWave)>(
                    SherpaOnnxReadWaveFromBinaryData(static_cast<const char *>(wave.bytes), (int32_t)wave.length), SherpaOnnxFreeWave);
                if (!audio || audio->sample_rate < 8000 || audio->sample_rate > 48000 ||
                    audio->num_samples < audio->sample_rate * 0.15 || audio->num_samples > audio->sample_rate * 31)
                    error = SpeechError(2, @"请录制 0.15 到 30 秒的清晰人声。");
                else {
                    double energy = 0;
                    for (int32_t i = 0; i < audio->num_samples; ++i) energy += audio->samples[i] * audio->samples[i];
                    if (std::sqrt(energy / audio->num_samples) < 0.001) text = @"";
                    else if (![self loadRecognizer]) error = SpeechError(3, @"手机内的语音识别模型未能载入。");
                    else if (token != self->_generation.load()) error = Cancelled();
                    else {
                        auto stream = std::unique_ptr<const SherpaOnnxOfflineStream, decltype(&SherpaOnnxDestroyOfflineStream)>(
                            SherpaOnnxCreateOfflineStream(self->_recognizer), SherpaOnnxDestroyOfflineStream);
                        if (!stream) error = SpeechError(4, @"无法创建语音识别任务。");
                        else {
                            SherpaOnnxAcceptWaveformOffline(stream.get(), audio->sample_rate, audio->samples, audio->num_samples);
                            SherpaOnnxDecodeOfflineStream(self->_recognizer, stream.get());
                            auto result = std::unique_ptr<const SherpaOnnxOfflineRecognizerResult, decltype(&SherpaOnnxDestroyOfflineRecognizerResult)>(
                                SherpaOnnxGetOfflineStreamResult(stream.get()), SherpaOnnxDestroyOfflineRecognizerResult);
                            if (!result) error = SpeechError(5, @"语音识别失败，请重试。");
                            else text = [[NSString stringWithUTF8String:result->text] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                        }
                    }
                }
            }
        } catch (const std::exception &) { error = SpeechError(6, @"语音识别暂时不可用，请重试。"); }
        if (token != self->_generation.load()) { text = nil; error = Cancelled(); }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(text, error); });
    }});
}
- (void)synthesize:(NSString *)text speed:(double)speed completion:(void (^)(NSData *, NSError *))completion {
    uint64_t token = _generation.load();
    dispatch_async(_queue, ^{ @autoreleasepool {
        NSData *wave = nil; NSError *error = nil;
        try {
            if (token != self->_generation.load()) error = Cancelled();
            else if (!text.length || text.length > 1000 || !std::isfinite(speed)) error = SpeechError(7, @"朗读文字无效或过长。");
            else if (![self loadSynthesizer]) error = SpeechError(8, @"手机内的朗读模型未能载入。");
            else if (token != self->_generation.load()) error = Cancelled();
            else {
                SherpaOnnxGenerationConfig config = {};
                config.sid = 0; config.speed = (float)std::clamp(speed, 0.7, 1.4); config.silence_scale = 0.2f;
                Cancellation state = { &self->_generation, token };
                auto audio = std::unique_ptr<const SherpaOnnxGeneratedAudio, decltype(&SherpaOnnxDestroyOfflineTtsGeneratedAudio)>(
                    SherpaOnnxOfflineTtsGenerateWithConfig(self->_tts, text.UTF8String, &config, Progress, &state), SherpaOnnxDestroyOfflineTtsGeneratedAudio);
                if (!audio || audio->n <= 0) error = SpeechError(9, @"这段文字没有生成可播放的声音。");
                else if (token == self->_generation.load()) wave = WaveData(audio.get());
            }
        } catch (const std::exception &) { error = SpeechError(10, @"朗读暂时不可用，请重试。"); }
        if (token != self->_generation.load()) { wave = nil; error = Cancelled(); }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(wave, error); });
    }});
}
@end
