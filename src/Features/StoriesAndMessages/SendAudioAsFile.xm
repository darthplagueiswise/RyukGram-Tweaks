// Send audio/video files as voice messages in DMs.
// Injects an Upload Audio item into the DM plus menu, runs the file through a
// trim UI, transcodes to AAC m4a (or passes formats IG accepts as-is), then
// hands the URL to IG's native voice pipeline.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../SCIFFmpeg.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <AVFoundation/AVFoundation.h>

typedef id (*SCIMsgSend)(id, SEL);
static inline id sciAF(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((SCIMsgSend)objc_msgSend)(obj, sel);
}

static __weak UIViewController *sciAudioThreadVC = nil;
static BOOL sciDMMenuPending = NO;

#pragma mark - Send audio through IG pipeline

static NSSet<NSString *> *sciPassthroughAudioExts(void);

static void sciSendAudioFile(NSURL *audioURL, UIViewController *threadVC) {
    AVAsset *asset = [AVAsset assetWithURL:audioURL];
    double duration = CMTimeGetSeconds(asset.duration);
    // AVFoundation returns 0/NaN for containers it can't parse (e.g. Ogg).
    if (duration <= 0 || isnan(duration)) duration = 1.0;

    id voiceController = sciAF(threadVC, @selector(voiceController));
    id voiceRecordVC = nil;
    if (voiceController) {
        Ivar vrIvar = class_getInstanceVariable([voiceController class], "_voiceRecordViewController");
        voiceRecordVC = vrIvar ? object_getIvar(voiceController, vrIvar) : nil;
    }

    id waveform = nil;
    Class wfClass = NSClassFromString(@"IGDirectAudioWaveform");
    NSMutableArray *fallbackArr = [NSMutableArray array];
    for (int i = 0; i < MAX(10, MIN((int)(duration * 10), 300)); i++)
        [fallbackArr addObject:@(0.1 + arc4random_uniform(80) / 100.0)];

    if (wfClass) {
        NSArray *rawData = nil;
        SEL genSel = @selector(generateWaveformDataFromAudioFile:maxLength:);
        if ([wfClass respondsToSelector:genSel]) {
            typedef id (*GenFn)(id, SEL, id, NSInteger);
            rawData = ((GenFn)objc_msgSend)(wfClass, genSel, audioURL, (NSInteger)(duration * 10));
        }
        if (!rawData) rawData = fallbackArr;

        SEL scaleSel = @selector(scaledArrayOfNumbers:);
        if ([wfClass respondsToSelector:scaleSel]) {
            typedef id (*ScaleFn)(id, SEL, id);
            NSArray *scaled = ((ScaleFn)objc_msgSend)(wfClass, scaleSel, rawData);
            if (scaled) rawData = scaled;
        }

        SEL initWF = @selector(initWithVolumeRecordingInterval:averageVolume:);
        if ([wfClass instancesRespondToSelector:initWF]) {
            typedef id (*InitFn)(id, SEL, double, id);
            waveform = ((InitFn)objc_msgSend)([wfClass alloc], initWF, 0.1, rawData);
        }
        if (!waveform) {
            waveform = [[wfClass alloc] init];
            for (NSString *n in @[@"_averageVolume", @"_waveformData", @"_data", @"_volumes"]) {
                Ivar iv = class_getInstanceVariable(wfClass, [n UTF8String]);
                if (iv) { object_setIvar(waveform, iv, rawData); break; }
            }
        }
    }
    if (!waveform) waveform = fallbackArr;

    @try {
        SEL vmSel = @selector(visualMessageViewerPresentationManagerDidRecordAudioClipWithURL:waveform:duration:entryPoint:toReplyToMessageWithID:);
        if ([threadVC respondsToSelector:vmSel]) {
            typedef void (*Fn)(id, SEL, id, id, double, NSInteger, id);
            ((Fn)objc_msgSend)(threadVC, vmSel, audioURL, waveform, duration, (NSInteger)2, nil);
            [SCIUtils showToastForDuration:1.5 title:SCILocalized(@"Audio sent")];
            return;
        }
        SEL s7 = @selector(voiceRecordViewController:didRecordAudioClipWithURL:waveform:duration:entryPoint:aiVoiceEffectApplied:sendButtonTypeTapped:);
        if ([threadVC respondsToSelector:s7]) {
            typedef void (*Fn)(id, SEL, id, id, id, CGFloat, NSInteger, id, id);
            ((Fn)objc_msgSend)(threadVC, s7, voiceRecordVC, audioURL, waveform, (CGFloat)duration, (NSInteger)2, nil, nil);
            [SCIUtils showToastForDuration:1.5 title:SCILocalized(@"Audio sent")];
            return;
        }
        SEL s5 = @selector(voiceRecordViewController:didRecordAudioClipWithURL:waveform:duration:entryPoint:);
        if ([threadVC respondsToSelector:s5]) {
            typedef void (*Fn)(id, SEL, id, id, id, CGFloat, NSInteger);
            ((Fn)objc_msgSend)(threadVC, s5, voiceRecordVC, audioURL, waveform, (CGFloat)duration, (NSInteger)2);
            [SCIUtils showToastForDuration:1.5 title:SCILocalized(@"Audio sent")];
            return;
        }
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No voice send method found")];
    } @catch (NSException *e) {
        [SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"Send failed: %@"), e.reason]];
    }
}

#pragma mark - Audio conversion with optional trim

// Unified failure alert: explains why, lets the user try sending raw, and links
// to the GitHub issues page for format requests.
static void sciShowUnsupportedAlert(NSURL *url, NSString *reason, UIViewController *threadVC) {
    NSString *fileExt = [[url pathExtension] lowercaseString];
    NSString *displayExt = (fileExt.length > 0) ? [NSString stringWithFormat:@".%@", fileExt] : @"This file";
    NSString *title = [NSString stringWithFormat:@"%@ can't be converted", displayExt];
    NSString *msg = [NSString stringWithFormat:
        @"iOS audio APIs couldn't process this file%@%@\n\n"
         "You can try sending it to Instagram as-is — IG's server may accept it "
         "(e.g. Opus/Ogg from web users), or it may silently fail.\n\n"
         "If you'd like RyukGram to support this format natively, open an issue:\n"
         "https://github.com/faroukbmiled/RyukGram/issues",
        reason.length > 0 ? @":\n" : @".",
        reason.length > 0 ? reason : @""];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak UIViewController *weakVC = threadVC;
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Send anyway") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        sciSendAudioFile(url, weakVC);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Open GitHub") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [[UIApplication sharedApplication]
            openURL:[NSURL URLWithString:@"https://github.com/faroukbmiled/RyukGram/issues"]
            options:@{} completionHandler:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *presenter = threadVC ?: [UIApplication sharedApplication].keyWindow.rootViewController;
    [presenter presentViewController:alert animated:YES completion:nil];
}

// FFmpeg path: any format → AAC M4A, with optional trim
static void sciFFmpegConvertAndSend(NSURL *url, UIViewController *threadVC, CMTimeRange trimRange) {
    BOOL hasTrim = CMTIMERANGE_IS_VALID(trimRange) && !CMTIMERANGE_IS_EMPTY(trimRange) &&
                   CMTimeGetSeconds(trimRange.duration) > 0;

    NSString *out = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"rg_ffaudio_%u.m4a", arc4random()]];
    [[NSFileManager defaultManager] removeItemAtPath:out error:nil];

    NSMutableString *cmd = [NSMutableString stringWithFormat:@"-y -i \"%@\"", url.path];
    if (hasTrim) {
        double ss = CMTimeGetSeconds(trimRange.start);
        double dur = CMTimeGetSeconds(trimRange.duration);
        [cmd appendFormat:@" -ss %.3f -t %.3f", ss, dur];
    }
    [cmd appendFormat:@" -vn -c:a aac -b:a 128k -ar 44100 -ac 1 \"%@\"", out];

    [SCIFFmpeg executeCommand:cmd completion:^(BOOL success, NSString *output) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success && [[NSFileManager defaultManager] fileExistsAtPath:out]) {
                sciSendAudioFile([NSURL fileURLWithPath:out], threadVC);
            } else {
                sciShowUnsupportedAlert(url, @"FFmpeg conversion failed", threadVC);
            }
        });
    }];
}

// AVFoundation fallback for iOS-native formats
static void sciAVFoundationConvertAndSend(NSURL *url, UIViewController *threadVC, CMTimeRange trimRange) {
    BOOL hasTrim = CMTIMERANGE_IS_VALID(trimRange) && !CMTIMERANGE_IS_EMPTY(trimRange) &&
                   CMTimeGetSeconds(trimRange.duration) > 0;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        AVAsset *asset = [AVAsset assetWithURL:url];
        AVAssetTrack *audioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
        if (!audioTrack) {
            dispatch_async(dispatch_get_main_queue(), ^{
                sciShowUnsupportedAlert(url, @"no audio track could be read", threadVC);
            });
            return;
        }

        AVMutableComposition *comp = [AVMutableComposition composition];
        AVMutableCompositionTrack *ct = [comp addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];

        CMTimeRange sourceRange = hasTrim ? trimRange : CMTimeRangeMake(kCMTimeZero, asset.duration);
        NSError *insertErr = nil;
        [ct insertTimeRange:sourceRange ofTrack:audioTrack atTime:kCMTimeZero error:&insertErr];
        if (insertErr) {
            dispatch_async(dispatch_get_main_queue(), ^{
                sciShowUnsupportedAlert(url, insertErr.localizedDescription, threadVC);
            });
            return;
        }

        NSString *out = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"rg_exp_%u.m4a", arc4random()]];
        [[NSFileManager defaultManager] removeItemAtPath:out error:nil];

        AVAssetExportSession *exp = [AVAssetExportSession exportSessionWithAsset:comp presetName:AVAssetExportPresetAppleM4A];
        exp.outputURL = [NSURL fileURLWithPath:out];
        exp.outputFileType = AVFileTypeAppleM4A;

        [exp exportAsynchronouslyWithCompletionHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (exp.status == AVAssetExportSessionStatusCompleted) {
                    sciSendAudioFile([NSURL fileURLWithPath:out], threadVC);
                } else {
                    sciShowUnsupportedAlert(url, exp.error.localizedDescription, threadVC);
                }
            });
        }];
    });
}

static void sciExportAndSend(NSURL *url, UIViewController *threadVC, BOOL isVideo, CMTimeRange trimRange) {
    BOOL hasTrim = CMTIMERANGE_IS_VALID(trimRange) && !CMTIMERANGE_IS_EMPTY(trimRange) &&
                   CMTimeGetSeconds(trimRange.duration) > 0;

    // Passthrough formats IG accepts directly (no conversion needed, trim ignored)
    NSString *ext = [[url pathExtension] lowercaseString];
    if (!isVideo && !hasTrim && [sciPassthroughAudioExts() containsObject:ext]) {
        sciSendAudioFile(url, threadVC);
        return;
    }

    [SCIUtils showToastForDuration:1.5 title:isVideo ? SCILocalized(@"Extracting audio...") : SCILocalized(@"Converting...")];

    // FFmpeg handles any format + video→audio extraction
    if ([SCIFFmpeg isAvailable]) {
        sciFFmpegConvertAndSend(url, threadVC, trimRange);
        return;
    }

    // Passthrough without trim when no FFmpeg
    if (!isVideo && [sciPassthroughAudioExts() containsObject:ext]) {
        sciSendAudioFile(url, threadVC);
        return;
    }

    // AVFoundation fallback
    sciAVFoundationConvertAndSend(url, threadVC, trimRange);
}

// Formats IG accepts as-is (no conversion needed)
static NSSet<NSString *> *sciPassthroughAudioExts(void) {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[@"m4a", @"aac", @"ogg", @"opus"]];
    });
    return set;
}

static void sciConvertAndSend(NSURL *url, UIViewController *threadVC, BOOL isVideo) {
    NSString *ext = [[url pathExtension] lowercaseString];
    if (!isVideo && [sciPassthroughAudioExts() containsObject:ext]) {
        sciSendAudioFile(url, threadVC);
        return;
    }
    sciExportAndSend(url, threadVC, isVideo, kCMTimeRangeInvalid);
}

#pragma mark - Audio/Video trim VC

@interface SCITrimViewController : UIViewController
@property (nonatomic, strong) NSURL *mediaURL;
@property (nonatomic, assign) BOOL isVideo;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UILabel *rangeLabel;
@property (nonatomic, strong) UIView *trackView;
@property (nonatomic, strong) UIView *selectedRange;
@property (nonatomic, strong) UIView *leftHandle;
@property (nonatomic, strong) UIView *rightHandle;
@property (nonatomic, strong) UIView *playhead;
@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic, assign) double totalDuration;
@property (nonatomic, assign) double startTime;
@property (nonatomic, assign) double endTime;
@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, weak) UIViewController *threadVC;
@end

static const CGFloat kTrackH = 56.0;
static const CGFloat kHandleW = 16.0;
static const CGFloat kHandleHitW = 48.0; // wide touch target
static const CGFloat kTrackMargin = 24.0;

@implementation SCITrimViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.08 alpha:1.0];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    AVAsset *asset = [AVAsset assetWithURL:self.mediaURL];
    self.totalDuration = CMTimeGetSeconds(asset.duration);
    self.startTime = 0;
    self.endTime = self.totalDuration;

    CGFloat w = self.view.bounds.size.width;
    CGFloat safeBottom = 34; // approximate safe area
    CGFloat bottomY = self.view.bounds.size.height - safeBottom;

    // ── send button (bottom, full width, thumb-reachable) ──
    UIButton *sendBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    sendBtn.frame = CGRectMake(kTrackMargin, bottomY - 56, w - kTrackMargin * 2, 50);
    sendBtn.backgroundColor = [UIColor systemBlueColor];
    sendBtn.layer.cornerRadius = 14;
    [sendBtn setTitle:SCILocalized(@"Send Audio") forState:UIControlStateNormal];
    [sendBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    sendBtn.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [sendBtn addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:sendBtn];

    // ── play/pause button ──
    CGFloat playY = sendBtn.frame.origin.y - 64;
    self.playBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playBtn.frame = CGRectMake(w / 2 - 28, playY, 56, 56);
    self.playBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
    self.playBtn.layer.cornerRadius = 28;
    UIImageSymbolConfiguration *playCfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    [self.playBtn setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:playCfg] forState:UIControlStateNormal];
    self.playBtn.tintColor = [UIColor whiteColor];
    [self.playBtn addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.playBtn];

    // ── range label (above play button) ──
    self.rangeLabel = [[UILabel alloc] initWithFrame:CGRectMake(kTrackMargin, playY - 36, w - kTrackMargin * 2, 24)];
    self.rangeLabel.textColor = [UIColor whiteColor];
    self.rangeLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightMedium];
    self.rangeLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.rangeLabel];

    // ── track (range selector) ──
    CGFloat trackY = self.rangeLabel.frame.origin.y - kTrackH - 20;

    // track background
    self.trackView = [[UIView alloc] initWithFrame:CGRectMake(kTrackMargin, trackY, w - kTrackMargin * 2, kTrackH)];
    self.trackView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    self.trackView.layer.cornerRadius = 10;
    self.trackView.clipsToBounds = YES;
    [self.view addSubview:self.trackView];

    // generate waveform bars
    [self generateWaveformBars];

    // selected range overlay
    self.selectedRange = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.trackView.bounds.size.width, kTrackH)];
    self.selectedRange.backgroundColor = [UIColor colorWithRed:0.35 green:0.5 blue:1.0 alpha:0.25];
    self.selectedRange.userInteractionEnabled = NO;
    self.selectedRange.layer.cornerRadius = 10;
    [self.trackView addSubview:self.selectedRange];

    // left handle — wide invisible hit area with narrow visual handle inside
    self.leftHandle = [[UIView alloc] initWithFrame:CGRectMake(-kHandleHitW / 2, -10, kHandleHitW, kTrackH + 20)];
    self.leftHandle.backgroundColor = [UIColor clearColor];
    self.leftHandle.userInteractionEnabled = YES;
    UIView *leftVisual = [self createHandleVisual];
    leftVisual.frame = CGRectMake((kHandleHitW - kHandleW) / 2, 10, kHandleW, kTrackH);
    leftVisual.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
    leftVisual.tag = 7001;
    [self.leftHandle addSubview:leftVisual];
    [self.trackView addSubview:self.leftHandle];

    UIPanGestureRecognizer *leftPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(leftHandlePan:)];
    [self.leftHandle addGestureRecognizer:leftPan];

    // right handle
    CGFloat trackW = self.trackView.bounds.size.width;
    self.rightHandle = [[UIView alloc] initWithFrame:CGRectMake(trackW - kHandleHitW / 2, -10, kHandleHitW, kTrackH + 20)];
    self.rightHandle.backgroundColor = [UIColor clearColor];
    self.rightHandle.userInteractionEnabled = YES;
    UIView *rightVisual = [self createHandleVisual];
    rightVisual.frame = CGRectMake((kHandleHitW - kHandleW) / 2, 10, kHandleW, kTrackH);
    rightVisual.layer.maskedCorners = kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
    rightVisual.tag = 7001;
    [self.rightHandle addSubview:rightVisual];
    [self.trackView addSubview:self.rightHandle];

    UIPanGestureRecognizer *rightPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(rightHandlePan:)];
    [self.rightHandle addGestureRecognizer:rightPan];

    // playhead
    self.playhead = [[UIView alloc] initWithFrame:CGRectMake(0, 2, 2.5, kTrackH - 4)];
    self.playhead.backgroundColor = [UIColor whiteColor];
    self.playhead.layer.cornerRadius = 1.25;
    self.playhead.hidden = YES;
    [self.trackView addSubview:self.playhead];

    // ── top area: icon + file info ──
    CGFloat topAreaY = 70;
    UIImageSymbolConfiguration *iconCfg = [UIImageSymbolConfiguration configurationWithPointSize:36 weight:UIImageSymbolWeightLight];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:self.isVideo ? @"video.fill" : @"waveform"
                                                                   withConfiguration:iconCfg]];
    icon.tintColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.frame = CGRectMake(w / 2 - 24, topAreaY, 48, 48);
    [self.view addSubview:icon];

    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, topAreaY + 56, w - 40, 20)];
    nameLabel.text = [self.mediaURL lastPathComponent];
    nameLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.4];
    nameLabel.font = [UIFont systemFontOfSize:13];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.view addSubview:nameLabel];

    self.durationLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, topAreaY + 78, w - 40, 20)];
    self.durationLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.3];
    self.durationLabel.font = [UIFont systemFontOfSize:12];
    self.durationLabel.textAlignment = NSTextAlignmentCenter;
    self.durationLabel.text = [NSString stringWithFormat:SCILocalized(@"Total: %@"), [self formatTime:self.totalDuration]];
    [self.view addSubview:self.durationLabel];

    // ── cancel X button (top-left) ──
    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    cancelBtn.frame = CGRectMake(12, 50, 36, 36);
    UIImageSymbolConfiguration *xCfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
    [cancelBtn setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:xCfg] forState:UIControlStateNormal];
    cancelBtn.tintColor = [UIColor colorWithWhite:1.0 alpha:0.6];
    cancelBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    cancelBtn.layer.cornerRadius = 18;
    [cancelBtn addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:cancelBtn];

    [self updateRangeUI];
}

- (void)generateWaveformBars {
    CGFloat trackW = self.trackView.bounds.size.width;
    int barCount = (int)(trackW / 4);
    CGFloat barW = 2.0;
    CGFloat gap = (trackW - barCount * barW) / (barCount - 1);

    for (int i = 0; i < barCount; i++) {
        CGFloat h = 8 + arc4random_uniform((unsigned int)(kTrackH - 16));
        CGFloat x = i * (barW + gap);
        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(x, (kTrackH - h) / 2, barW, h)];
        bar.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
        bar.layer.cornerRadius = 1;
        bar.tag = 8000 + i;
        [self.trackView insertSubview:bar atIndex:0];
    }
}

- (UIView *)createHandleVisual {
    UIView *handle = [[UIView alloc] init];
    handle.backgroundColor = [UIColor systemBlueColor];
    handle.layer.cornerRadius = 4;
    handle.userInteractionEnabled = NO;

    UIView *grip = [[UIView alloc] initWithFrame:CGRectMake(5, kTrackH / 2 - 8, 6, 16)];
    grip.userInteractionEnabled = NO;
    for (int i = 0; i < 2; i++) {
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(i * 4, 0, 1.5, 16)];
        line.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.7];
        line.layer.cornerRadius = 0.75;
        [grip addSubview:line];
    }
    [handle addSubview:grip];
    return handle;
}

- (CGFloat)timeToX:(double)time {
    CGFloat trackW = self.trackView.bounds.size.width;
    return (time / self.totalDuration) * trackW;
}

- (double)xToTime:(CGFloat)x {
    CGFloat trackW = self.trackView.bounds.size.width;
    double t = (x / trackW) * self.totalDuration;
    return MAX(0, MIN(t, self.totalDuration));
}

- (void)leftHandlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.trackView];
    [pan setTranslation:CGPointZero inView:self.trackView];

    CGFloat centerX = CGRectGetMidX(self.leftHandle.frame) + translation.x;
    double newTime = [self xToTime:centerX];
    newTime = MAX(0, MIN(newTime, self.endTime - 0.5));
    self.startTime = newTime;
    [self updateRangeUI];
}

- (void)rightHandlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.trackView];
    [pan setTranslation:CGPointZero inView:self.trackView];

    CGFloat centerX = CGRectGetMidX(self.rightHandle.frame) + translation.x;
    double newTime = [self xToTime:centerX];
    newTime = MIN(self.totalDuration, MAX(newTime, self.startTime + 0.5));
    self.endTime = newTime;
    [self updateRangeUI];
}

- (void)updateRangeUI {
    CGFloat leftX = [self timeToX:self.startTime];
    CGFloat rightX = [self timeToX:self.endTime];

    self.leftHandle.frame = CGRectMake(leftX - kHandleHitW / 2, -10, kHandleHitW, kTrackH + 20);
    self.rightHandle.frame = CGRectMake(rightX - kHandleHitW / 2, -10, kHandleHitW, kTrackH + 20);
    self.selectedRange.frame = CGRectMake(leftX, 0, rightX - leftX, kTrackH);

    double sel = self.endTime - self.startTime;
    self.rangeLabel.text = [NSString stringWithFormat:@"%@  —  %@    (%@)",
        [self formatTime:self.startTime], [self formatTime:self.endTime], [self formatDuration:sel]];
}

- (NSString *)formatTime:(double)secs {
    int m = (int)secs / 60;
    int s = (int)secs % 60;
    return [NSString stringWithFormat:@"%d:%02d", m, s];
}

- (NSString *)formatDuration:(double)secs {
    if (secs < 60) return [NSString stringWithFormat:@"%.1fs", secs];
    int m = (int)secs / 60;
    double s = secs - m * 60;
    return [NSString stringWithFormat:@"%dm %.0fs", m, s];
}

- (void)playPauseTapped {
    if (self.isPlaying) {
        [self stopPlayback];
    } else {
        [self startPlayback];
    }
}

- (void)startPlayback {
    [self stopPlayback];
    self.player = [AVPlayer playerWithURL:self.mediaURL];
    [self.player seekToTime:CMTimeMakeWithSeconds(self.startTime, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    self.playhead.hidden = NO;
    self.isPlaying = YES;

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    [self.playBtn setImage:[UIImage systemImageNamed:@"pause.fill" withConfiguration:cfg] forState:UIControlStateNormal];

    __weak SCITrimViewController *weakSelf = self;
    self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.05, 600) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        SCITrimViewController *s = weakSelf;
        if (!s) return;
        double current = CMTimeGetSeconds(time);
        if (current >= s.endTime) {
            [s stopPlayback];
            return;
        }
        CGFloat x = [s timeToX:current];
        s.playhead.frame = CGRectMake(x - 1.25, 2, 2.5, kTrackH - 4);
    }];

    [self.player play];
}

- (void)stopPlayback {
    if (self.timeObserver && self.player) {
        [self.player removeTimeObserver:self.timeObserver];
    }
    self.timeObserver = nil;
    [self.player pause];
    self.player = nil;
    self.isPlaying = NO;
    self.playhead.hidden = YES;

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    [self.playBtn setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:cfg] forState:UIControlStateNormal];
}

- (void)cancelTapped {
    [self stopPlayback];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)sendTapped {
    [self stopPlayback];
    double dur = self.endTime - self.startTime;
    if (dur < 0.5) {
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Selection too short (min 0.5s)")];
        return;
    }

    UIViewController *tvc = self.threadVC;
    NSURL *url = self.mediaURL;
    BOOL video = self.isVideo;
    CMTimeRange trimRange = CMTimeRangeMake(CMTimeMakeWithSeconds(self.startTime, 600), CMTimeMakeWithSeconds(dur, 600));

    [self dismissViewControllerAnimated:YES completion:^{
        if (tvc) sciExportAndSend(url, tvc, video, trimRange);
    }];
}

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

@end

static void sciShowTrimVC(NSURL *url, BOOL isVideo, UIViewController *threadVC) {
    SCITrimViewController *trimVC = [[SCITrimViewController alloc] init];
    trimVC.mediaURL = url;
    trimVC.isVideo = isVideo;
    trimVC.threadVC = threadVC;
    trimVC.modalPresentationStyle = UIModalPresentationFullScreen;
    [threadVC presentViewController:trimVC animated:YES completion:nil];
}

#pragma mark - Show picker options

static void sciShowUploadAudioOptions(UIViewController *threadVC) {
    sciAudioThreadVC = threadVC;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Upload Audio")
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    __weak UIViewController *weakVC = threadVC;

    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Audio/Video from Files") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIViewController *vc = weakVC;
        if (!vc) return;
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSArray *types = [SCIFFmpeg isAvailable]
            ? @[@"public.audio", @"public.audiovisual-content"]
            : @[@"public.audio", @"public.mpeg-4-audio", @"public.mp3", @"com.microsoft.waveform-audio",
                @"public.aiff-audio", @"com.apple.m4a-audio",
                @"public.movie", @"public.mpeg-4", @"com.apple.quicktime-movie"];
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
            initWithDocumentTypes:types inMode:UIDocumentPickerModeImport];
        #pragma clang diagnostic pop
        picker.delegate = (id<UIDocumentPickerDelegate>)vc;
        [vc presentViewController:picker animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Video from Library") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIViewController *vc = weakVC;
        if (!vc) return;
        UIImagePickerController *imgPicker = [[UIImagePickerController alloc] init];
        imgPicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        imgPicker.mediaTypes = @[@"public.movie"];
        imgPicker.delegate = (id<UINavigationControllerDelegate, UIImagePickerControllerDelegate>)vc;
        imgPicker.videoExportPreset = AVAssetExportPresetPassthrough;
        imgPicker.allowsEditing = YES; // enables built-in video trimming
        [vc presentViewController:imgPicker animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [threadVC presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Hook IGDSMenu to inject native menu item

%hook IGDSMenu

- (id)initWithMenuItems:(NSArray *)items edr:(BOOL)edr headerLabelText:(id)header {
    if (![SCIUtils getBoolPref:@"send_audio_as_file"]) return %orig;

    // Only inject into DM plus menus — sciDMMenuPending is set right before
    // this menu is created by the composer overflow button callback
    if (!sciDMMenuPending) return %orig;
    sciDMMenuPending = NO;

    for (id item in items) {
        id title = sciAF(item, @selector(title));
        if ([title isKindOfClass:[NSString class]] && [title isEqualToString:@"Upload Audio"]) return %orig;
    }

    Class itemClass = NSClassFromString(@"IGDSMenuItem");
    if (!itemClass) return %orig;

    UIImage *img = [[UIImage systemImageNamed:@"waveform"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

    void (^handler)(void) = ^{
        UIViewController *threadVC = sciAudioThreadVC;
        if (threadVC) sciShowUploadAudioOptions(threadVC);
    };

    SEL initSel = @selector(initWithTitle:image:handler:);
    if (![itemClass instancesRespondToSelector:initSel]) return %orig;

    typedef id (*InitFn)(id, SEL, id, id, id);
    id audioItem = ((InitFn)objc_msgSend)([itemClass alloc], initSel, @"Upload Audio", img, handler);
    if (!audioItem) return %orig;

    NSMutableArray *newItems = [NSMutableArray arrayWithObject:audioItem];
    [newItems addObjectsFromArray:items];

    return %orig(newItems, edr, header);
}

%end

#pragma mark - Hook IGDirectThreadViewController

%hook IGDirectThreadViewController

- (void)composerOverflowButtonMenuWillPrepareExpandWithPlusButton:(id)plusButton {
    %orig;
    if (![SCIUtils getBoolPref:@"send_audio_as_file"]) return;
    sciAudioThreadVC = self;
    sciDMMenuPending = YES;
}

// Convert unsupported formats to M4A before showing trim UI
static void sciPrepareAndShowTrim(NSURL *url, UIViewController *threadVC) {
    AVAsset *asset = [AVAsset assetWithURL:url];
    double dur = CMTimeGetSeconds(asset.duration);
    BOOL avCanRead = dur > 0 && !isnan(dur);
    BOOL isVideo = [[asset tracksWithMediaType:AVMediaTypeVideo] count] > 0;

    if (avCanRead) {
        sciShowTrimVC(url, isVideo, threadVC);
        return;
    }

    // AVFoundation can't read it — pre-convert with FFmpeg
    if ([SCIFFmpeg isAvailable]) {
        [SCIUtils showToastForDuration:1.5 title:SCILocalized(@"Converting...")];
        NSString *out = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"rg_pre_%u.m4a", arc4random()]];
        [[NSFileManager defaultManager] removeItemAtPath:out error:nil];

        NSString *cmd = [NSString stringWithFormat:@"-y -i \"%@\" -vn -c:a aac -b:a 128k -ar 44100 \"%@\"", url.path, out];
        [SCIFFmpeg executeCommand:cmd completion:^(BOOL success, NSString *output) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success && [[NSFileManager defaultManager] fileExistsAtPath:out]) {
                    sciShowTrimVC([NSURL fileURLWithPath:out], NO, threadVC);
                } else {
                    sciShowUnsupportedAlert(url, @"FFmpeg conversion failed", threadVC);
                }
            });
        }];
        return;
    }

    // No FFmpeg, can't read — unsupported
    sciShowUnsupportedAlert(url, @"Format not supported without FFmpegKit", threadVC);
}

// File picker delegate
%new - (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    sciPrepareAndShowTrim(url, self);
}

%new - (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    if (!url) return;
    sciPrepareAndShowTrim(url, self);
}

%new - (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {}

// video picker delegate — UIImagePickerController with allowsEditing handles trimming
%new - (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSURL *videoURL = info[UIImagePickerControllerMediaURL];
    if (!videoURL) {
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not get video URL")];
        return;
    }
    // UIImagePickerController with allowsEditing already trimmed the video for us
    sciConvertAndSend(videoURL, self, YES);
}

%new - (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

%end
