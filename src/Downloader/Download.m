#import "Download.h"
#import "../PhotoAlbum.h"
#import <Photos/Photos.h>

#pragma mark - Ticket slot

@interface SCIDownloadSlot : NSObject
@property (nonatomic, copy) NSString *ticketId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) float progress;
@property (nonatomic, copy) void (^onCancel)(void);
@property (nonatomic, assign) BOOL finished;
@end
@implementation SCIDownloadSlot @end

#pragma mark - SCIDownloadPillView

@interface SCIDownloadPillView ()
@property (nonatomic, strong) NSMutableArray<SCIDownloadSlot *> *slots;
@end

@implementation SCIDownloadPillView

+ (instancetype)shared {
    static SCIDownloadPillView *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SCIDownloadPillView alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _slots = [NSMutableArray array];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(_sciAppDidBecomeActive)
            name:UIApplicationDidBecomeActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(_sciAppDidEnterBackground)
            name:UIApplicationDidEnterBackgroundNotification object:nil];
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
        UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        blurView.translatesAutoresizingMaskIntoConstraints = NO;
        blurView.layer.cornerRadius = 16;
        blurView.clipsToBounds = YES;
        [self addSubview:blurView];
        [NSLayoutConstraint activateConstraints:@[
            [blurView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [blurView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [blurView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [blurView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];

        self.layer.cornerRadius = 16;
        self.clipsToBounds = YES;
        self.alpha = 0;

        // Icon
        _iconView = [[UIImageView alloc] init];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.tintColor = [UIColor whiteColor];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
        _iconView.image = [UIImage systemImageNamed:@"arrow.down.circle" withConfiguration:cfg];
        [self addSubview:_iconView];

        // Text
        _textLabel = [[UILabel alloc] init];
        _textLabel.text = SCILocalized(@"Downloading...");
        _textLabel.textColor = [UIColor whiteColor];
        _textLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _textLabel.textAlignment = NSTextAlignmentCenter;
        _textLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_textLabel];

        // Subtitle
        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.text = SCILocalized(@"Tap to cancel");
        _subtitleLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
        _subtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
        _subtitleLabel.textAlignment = NSTextAlignmentCenter;
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_subtitleLabel];

        // Progress bar
        _progressBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _progressBar.progressTintColor = [UIColor systemBlueColor];
        _progressBar.trackTintColor = [UIColor colorWithWhite:0.3 alpha:0.5];
        _progressBar.translatesAutoresizingMaskIntoConstraints = NO;
        _progressBar.layer.cornerRadius = 1.5;
        _progressBar.clipsToBounds = YES;
        [self addSubview:_progressBar];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-2],
            [_iconView.widthAnchor constraintEqualToConstant:22],
            [_iconView.heightAnchor constraintEqualToConstant:22],

            [_textLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
            [_textLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:10],
            [_textLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],

            [_subtitleLabel.topAnchor constraintEqualToAnchor:_textLabel.bottomAnchor constant:1],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_textLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_textLabel.trailingAnchor],

            [_progressBar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_progressBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_progressBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_progressBar.heightAnchor constraintEqualToConstant:3],

            [_subtitleLabel.bottomAnchor constraintEqualToAnchor:_progressBar.topAnchor constant:-8],
        ]];
    }
    return self;
}

- (void)handleTap {
    if (self.slots.count > 0) {
        SCIDownloadSlot *top = self.slots.lastObject;
        void (^cb)(void) = top.onCancel;
        top.onCancel = nil;
        if (cb) cb();
        return;
    }
    void (^cb)(void) = self.onCancel;
    self.onCancel = nil;
    if (cb) cb();
}

- (void)resetState {
    self.progressBar.progress = 0;
    self.progressBar.hidden = NO;
    self.subtitleLabel.hidden = NO;
    self.subtitleLabel.text = SCILocalized(@"Tap to cancel");
    self.textLabel.text = SCILocalized(@"Downloading...");
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    self.iconView.image = [UIImage systemImageNamed:@"arrow.down.circle" withConfiguration:cfg];
    self.iconView.tintColor = [UIColor whiteColor];
}

- (void)showInView:(UIView *)view {
    [self removeFromSuperview];
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:self];

    [NSLayoutConstraint activateConstraints:@[
        [self.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [self.widthAnchor constraintGreaterThanOrEqualToConstant:200],
        [self.widthAnchor constraintLessThanOrEqualToConstant:300],
    ]];

    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.alpha = 1;
    } completion:nil];
}

- (void)dismiss {
    dispatch_async(dispatch_get_main_queue(), ^{
        // A new ticket raced in — keep the pill alive.
        if (self.slots.count > 0) return;
        if (self.alpha <= 0.01 && !self.superview) return;
        self.onCancel = nil;
        [UIView animateWithDuration:0.25 animations:^{
            self.alpha = 0;
            self.transform = CGAffineTransformMakeScale(0.9, 0.9);
        } completion:^(BOOL finished) {
            [self removeFromSuperview];
            self.transform = CGAffineTransformIdentity;
        }];
    });
}

- (void)dismissAfterDelay:(NSTimeInterval)delay {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self dismiss];
    });
}

- (void)setProgress:(float)progress {
    self.progressBar.hidden = NO;
    [self.progressBar setProgress:progress animated:YES];
}

- (void)setText:(NSString *)text {
    self.textLabel.text = text;
}

- (void)setSubtitle:(NSString *)text {
    self.subtitleLabel.text = text;
    self.subtitleLabel.hidden = (text.length == 0);
}

- (void)showSuccess:(NSString *)text {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    self.iconView.image = [UIImage systemImageNamed:@"checkmark.circle.fill" withConfiguration:cfg];
    self.iconView.tintColor = [UIColor systemGreenColor];
    self.textLabel.text = text;
    self.subtitleLabel.hidden = YES;
    self.progressBar.hidden = YES;
    self.onCancel = nil;
}

- (void)showError:(NSString *)text {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    self.iconView.image = [UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:cfg];
    self.iconView.tintColor = [UIColor systemRedColor];
    self.textLabel.text = text;
    self.subtitleLabel.hidden = YES;
    self.progressBar.hidden = YES;
    self.onCancel = nil;
}

- (void)showBulkProgress:(NSUInteger)completed total:(NSUInteger)total {
    self.textLabel.text = [NSString stringWithFormat:@"Downloading %lu of %lu", (unsigned long)completed + 1, (unsigned long)total];
    self.subtitleLabel.text = SCILocalized(@"Tap to cancel");
    self.subtitleLabel.hidden = NO;
    self.progressBar.hidden = NO;
    [self.progressBar setProgress:(float)completed / (float)total animated:YES];
}

#pragma mark - Ticket API

- (void)_onMain:(dispatch_block_t)block {
    if ([NSThread isMainThread]) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

- (SCIDownloadSlot *)_slotForId:(NSString *)ticketId {
    if (!ticketId) return nil;
    for (SCIDownloadSlot *s in self.slots) {
        if ([s.ticketId isEqualToString:ticketId]) return s;
    }
    return nil;
}

- (void)_renderTop {
    SCIDownloadSlot *top = self.slots.lastObject;
    if (!top) return;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    self.iconView.image = [UIImage systemImageNamed:@"arrow.down.circle" withConfiguration:cfg];
    self.iconView.tintColor = [UIColor whiteColor];
    self.textLabel.text = top.title ?: @"Downloading...";
    self.progressBar.hidden = NO;
    [self.progressBar setProgress:top.progress animated:YES];
    self.subtitleLabel.hidden = NO;
    if (self.slots.count > 1) {
        self.subtitleLabel.text = [NSString stringWithFormat:@"%lu active — tap to cancel",
                                   (unsigned long)self.slots.count];
    } else {
        self.subtitleLabel.text = SCILocalized(@"Tap to cancel");
    }
}

- (NSString *)beginTicketWithTitle:(NSString *)title onCancel:(void (^)(void))cancel {
    NSString *ticketId = [[NSUUID UUID] UUIDString];
    void (^cancelCopy)(void) = [cancel copy];
    [self _onMain:^{
        SCIDownloadSlot *slot = [SCIDownloadSlot new];
        slot.ticketId = ticketId;
        slot.title = title ?: @"Downloading...";
        slot.progress = 0;
        slot.onCancel = cancelCopy;
        [self.slots addObject:slot];

        // Reset visual state so the prior download's final frame doesn't leak in.
        [self.progressBar setProgress:0 animated:NO];
        self.alpha = 1;
        self.transform = CGAffineTransformIdentity;
        if (!self.superview) {
            UIView *host = [UIApplication sharedApplication].keyWindow ?: topMostController().view;
            if (host) [self showInView:host];
        }
        [self _renderTop];
    }];
    return ticketId;
}

- (void)_sciAppDidBecomeActive {
    [self _onMain:^{
        if (self.slots.count == 0 && (self.superview || self.alpha > 0.01)) {
            self.alpha = 0;
            self.transform = CGAffineTransformIdentity;
            [self removeFromSuperview];
        } else if (self.slots.count > 0) {
            [self _renderTop];
        }
    }];
}

// iOS suspends networking + ffmpeg on background — cancel active tickets so the
// pill clears cleanly on return. User re-initiates the download.
- (void)_sciAppDidEnterBackground {
    [self _onMain:^{
        for (SCIDownloadSlot *slot in [self.slots copy]) {
            void (^cb)(void) = slot.onCancel;
            slot.onCancel = nil;
            if (cb) cb();
        }
    }];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)updateTicket:(NSString *)ticketId progress:(float)progress {
    [self _onMain:^{
        SCIDownloadSlot *s = [self _slotForId:ticketId];
        if (!s || s.finished) return;
        s.progress = progress;
        if (self.slots.lastObject == s) [self.progressBar setProgress:progress animated:YES];
    }];
}

- (void)updateTicket:(NSString *)ticketId text:(NSString *)text {
    [self _onMain:^{
        SCIDownloadSlot *s = [self _slotForId:ticketId];
        if (!s || s.finished) return;
        s.title = text ?: s.title;
        if (self.slots.lastObject == s) self.textLabel.text = s.title;
    }];
}

- (void)_removeSlot:(SCIDownloadSlot *)slot
        finalText:(NSString *)finalText
        finalIcon:(NSString *)finalIcon
        iconColor:(UIColor *)iconColor {
    if (!slot || slot.finished) return;
    slot.finished = YES;
    slot.onCancel = nil;
    [self.slots removeObject:slot];

    if (self.slots.count > 0) {
        [self _renderTop];
        return;
    }

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    self.iconView.image = [UIImage systemImageNamed:finalIcon withConfiguration:cfg];
    self.iconView.tintColor = iconColor;
    self.textLabel.text = finalText;
    self.subtitleLabel.hidden = YES;
    self.progressBar.hidden = YES;
    [self dismissAfterDelay:1.2];
}

- (void)finishTicket:(NSString *)ticketId successMessage:(NSString *)message {
    [self _onMain:^{
        SCIDownloadSlot *s = [self _slotForId:ticketId];
        [self _removeSlot:s
                finalText:message ?: @"Done"
                finalIcon:@"checkmark.circle.fill"
                iconColor:[UIColor systemGreenColor]];
    }];
}

- (void)finishTicket:(NSString *)ticketId errorMessage:(NSString *)message {
    [self _onMain:^{
        SCIDownloadSlot *s = [self _slotForId:ticketId];
        [self _removeSlot:s
                finalText:message ?: @"Failed"
                finalIcon:@"xmark.circle.fill"
                iconColor:[UIColor systemRedColor]];
    }];
}

- (void)finishTicket:(NSString *)ticketId cancelled:(NSString *)message {
    [self _onMain:^{
        SCIDownloadSlot *s = [self _slotForId:ticketId];
        [self _removeSlot:s
                finalText:message ?: @"Cancelled"
                finalIcon:@"xmark.circle.fill"
                iconColor:[UIColor systemOrangeColor]];
    }];
}

@end


#pragma mark - SCIDownloadDelegate

@implementation SCIDownloadDelegate

- (instancetype)initWithAction:(DownloadAction)action showProgress:(BOOL)showProgress {
    self = [super init];

    if (self) {
        _action = action;
        _showProgress = showProgress;
        self.downloadManager = [[SCIDownloadManager alloc] initWithDelegate:self];
    }

    return self;
}

- (void)downloadFileWithURL:(NSURL *)url fileExtension:(NSString *)fileExtension hudLabel:(NSString *)hudLabel {
    SCIDownloadPillView *pill = [SCIDownloadPillView shared];
    self.pill = pill;

    __weak typeof(self) weakSelf = self;
    self.ticketId = [pill beginTicketWithTitle:hudLabel ?: @"Downloading..." onCancel:^{
        [weakSelf.downloadManager cancelDownload];
    }];

    NSLog(@"[SCInsta] Download: Will start download for url \"%@\" with file extension: \".%@\"", url, fileExtension);
    [self.downloadManager downloadFileWithURL:url fileExtension:fileExtension];
}

- (void)downloadDidStart {
    NSLog(@"[SCInsta] Download: Download started");
}

- (void)downloadDidCancel {
    [self.pill finishTicket:self.ticketId cancelled:@"Cancelled"];
    NSLog(@"[SCInsta] Download: Download cancelled");
}

- (void)downloadDidProgress:(float)progress {
    if (!self.showProgress) return;
    [self.pill updateTicket:self.ticketId progress:progress];
    [self.pill updateTicket:self.ticketId text:[NSString stringWithFormat:@"Downloading %d%%", (int)(progress * 100)]];
}

- (void)downloadDidFinishWithError:(NSError *)error {
    if (error && error.code != NSURLErrorCancelled) {
        NSLog(@"[SCInsta] Download: Download failed with error: \"%@\"", error);
        [self.pill finishTicket:self.ticketId errorMessage:SCILocalized(@"Download failed")];
    }
}

- (void)downloadDidFinishWithFileURL:(NSURL *)fileURL {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[SCInsta] Download: Finished with url: \"%@\"", [fileURL absoluteString]);
        // saveToPhotos finishes the ticket after the PH completion fires.
        if (self.action != saveToPhotos) {
            [self.pill finishTicket:self.ticketId successMessage:SCILocalized(@"Done")];
        }

        switch (self.action) {
            case share:
                [SCIUtils showShareVC:fileURL];
                break;

            case quickLook:
                [SCIUtils showQuickLookVC:@[fileURL]];
                break;

            case saveToPhotos: {
                [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                    if (status != PHAuthorizationStatusAuthorized) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Photo library access denied")];
                        });
                        return;
                    }

                    BOOL useAlbum = [SCIUtils getBoolPref:@"save_to_ryukgram_album"];
                    void (^onDone)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (success) {
                                [self.pill finishTicket:self.ticketId
                                         successMessage:useAlbum ? SCILocalized(@"Saved to RyukGram") : SCILocalized(@"Saved to Photos")];
                            } else {
                                [self.pill finishTicket:self.ticketId errorMessage:SCILocalized(@"Failed to save")];
                            }
                        });
                    };

                    if (useAlbum) {
                        [SCIPhotoAlbum saveFileToAlbum:fileURL completion:onDone];
                    } else {
                        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                            NSString *ext = [[fileURL pathExtension] lowercaseString];
                            BOOL isVideo = [@[@"mp4", @"mov", @"m4v"] containsObject:ext];
                            PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
                            PHAssetResourceCreationOptions *opts = [[PHAssetResourceCreationOptions alloc] init];
                            opts.shouldMoveFile = YES;
                            [req addResourceWithType:(isVideo ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto)
                                             fileURL:fileURL options:opts];
                            req.creationDate = [NSDate date];
                        } completionHandler:onDone];
                    }
                }];
                break;
            }
        }
    });
}

@end
