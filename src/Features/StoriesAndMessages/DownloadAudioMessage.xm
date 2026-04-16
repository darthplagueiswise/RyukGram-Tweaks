// Download voice messages from DMs. Detects audio messages via the
// menuConfiguration hook, then injects a Download item into the long-press
// PrismMenu. Tries to convert to .m4a; falls back to the source extension
// (e.g. .ogg from web users) if AVFoundation can't decode the format.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <AVFoundation/AVFoundation.h>
#import "../../Downloader/Download.h"

typedef id (*SCIMsgSendId)(id, SEL);
static inline id sciDAF(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((SCIMsgSendId)objc_msgSend)(obj, sel);
}

static BOOL sciAudioMenuPending = NO;
static id sciLastAudioViewModel = nil;

// Demangled: IGDirectMessageMenuConfiguration.IGDirectMessageMenuConfiguration
%hook _TtC32IGDirectMessageMenuConfiguration32IGDirectMessageMenuConfiguration

+ (id)menuConfigurationWithEligibleOptions:(id)options
                          messageViewModel:(id)arg2
                               contentType:(id)arg3
                                 isSticker:(_Bool)arg4
                            isMusicSticker:(_Bool)arg5
                          directNuxManager:(id)arg6
                       sessionUserDefaults:(id)arg7
                               launcherSet:(id)arg8
                               userSession:(id)arg9
                                tapHandler:(id)arg10
{
    if ([SCIUtils getBoolPref:@"download_audio_message"] &&
        [arg3 isKindOfClass:[NSString class]] && [arg3 isEqualToString:@"voice_media"]) {
        sciAudioMenuPending = YES;
        sciLastAudioViewModel = arg2;
    }
    return %orig;
}

%end

// PrismMenu uses Swift classes with mangled names — hook via MSHookMessageEx in %ctor.

static id (*orig_prismMenuView_init3)(id, SEL, NSArray *, id, BOOL);

static id new_prismMenuView_init3(id self, SEL _cmd, NSArray *elements, id header, BOOL edr) {
    if (!sciAudioMenuPending) return orig_prismMenuView_init3(self, _cmd, elements, header, edr);
    sciAudioMenuPending = NO;

    if (![SCIUtils getBoolPref:@"download_audio_message"])
        return orig_prismMenuView_init3(self, _cmd, elements, header, edr);

    Class builderClass = NSClassFromString(@"IGDSPrismMenuItemBuilder");
    Class elementClass = NSClassFromString(@"IGDSPrismMenuElement");
    if (!builderClass || !elementClass || elements.count == 0)
        return orig_prismMenuView_init3(self, _cmd, elements, header, edr);

    typedef id (*InitFn)(id, SEL, id);
    typedef id (*WithFn)(id, SEL, id);
    typedef id (*BuildFn)(id, SEL);

    id capturedVM = sciLastAudioViewModel;
    void (^handler)(void) = ^{
        if (!capturedVM) return;

        // vm -> audio (IGDirectAudio) -> _server_audio (IGAudio) -> playbackURL
        id directAudio = nil;
        @try { directAudio = [capturedVM valueForKey:@"audio"]; } @catch (NSException *e) {}
        if (!directAudio) {
            [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not get audio data. Try again after refreshing the chat.")];
            return;
        }

        Ivar serverAudioIvar = class_getInstanceVariable([directAudio class], "_server_audio");
        id serverAudio = serverAudioIvar ? object_getIvar(directAudio, serverAudioIvar) : nil;
        if (!serverAudio) {
            [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Audio not loaded yet. Play the message first and try again.")];
            return;
        }

        NSURL *playbackURL = sciDAF(serverAudio, @selector(playbackURL));
        if (!playbackURL) playbackURL = sciDAF(serverAudio, @selector(fallbackURL));
        if (!playbackURL) {
            [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No audio URL found. Try again after refreshing the chat.")];
            return;
        }

        UIView *topView = [UIApplication sharedApplication].keyWindow;
        SCIDownloadPillView *pill = [[SCIDownloadPillView alloc] init];
        [pill setText:SCILocalized(@"Downloading audio...")];
        [pill showInView:topView];

        NSURLSessionDownloadTask *task = [[NSURLSession sharedSession]
            downloadTaskWithURL:playbackURL
            completionHandler:^(NSURL *tempURL, NSURLResponse *response, NSError *error) {
            if (error || !tempURL) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [pill dismiss];
                    [SCIUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Download failed. Try again."];
                });
                return;
            }

            // Try to convert to .m4a; on failure (e.g. Ogg/Opus) keep the source extension.
            NSString *urlExt = [[playbackURL.path pathExtension] lowercaseString];
            if (urlExt.length == 0) urlExt = @"m4a";

            NSString *mediaId = sciDAF(serverAudio, @selector(mediaId)) ?: @"voice_message";
            NSString *srcPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat:@"tmp_%@.%@", mediaId, urlExt]];
            NSURL *srcURL = [NSURL fileURLWithPath:srcPath];
            [[NSFileManager defaultManager] removeItemAtURL:srcURL error:nil];
            [[NSFileManager defaultManager] moveItemAtURL:tempURL toURL:srcURL error:nil];

            void (^present)(NSURL *) = ^(NSURL *url) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [pill setText:SCILocalized(@"Done!")];
                    [pill dismissAfterDelay:0.5];
                    [SCIUtils showShareVC:url];
                });
            };

            NSString *m4aPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat:@"audio_%@.m4a", mediaId]];
            NSURL *m4aURL = [NSURL fileURLWithPath:m4aPath];
            [[NSFileManager defaultManager] removeItemAtURL:m4aURL error:nil];

            AVAsset *asset = [AVAsset assetWithURL:srcURL];
            AVAssetExportSession *exp = [AVAssetExportSession
                exportSessionWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
            exp.outputURL = m4aURL;
            exp.outputFileType = AVFileTypeAppleM4A;

            [exp exportAsynchronouslyWithCompletionHandler:^{
                if (exp.status == AVAssetExportSessionStatusCompleted) {
                    [[NSFileManager defaultManager] removeItemAtURL:srcURL error:nil];
                    present(m4aURL);
                    return;
                }
                // Conversion failed — keep the original with its real extension.
                [[NSFileManager defaultManager] removeItemAtURL:m4aURL error:nil];
                NSString *outPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"audio_%@.%@", mediaId, urlExt]];
                NSURL *outURL = [NSURL fileURLWithPath:outPath];
                [[NSFileManager defaultManager] removeItemAtURL:outURL error:nil];
                if (![[NSFileManager defaultManager] moveItemAtURL:srcURL toURL:outURL error:nil]) {
                    present(srcURL);
                    return;
                }
                present(outURL);
            }];
        }];
        [task resume];
    };

    id builder = ((InitFn)objc_msgSend)([builderClass alloc], @selector(initWithTitle:), @"Download");
    builder = ((WithFn)objc_msgSend)(builder, @selector(withImage:), [UIImage systemImageNamed:@"arrow.down.circle"]);
    builder = ((WithFn)objc_msgSend)(builder, @selector(withHandler:), handler);
    id menuItem = ((BuildFn)objc_msgSend)(builder, @selector(build));
    if (!menuItem) return orig_prismMenuView_init3(self, _cmd, elements, header, edr);

    // Wrap in IGDSPrismMenuElement: clone _subtype from a sibling, attach the menuItem.
    id templateEl = elements[0];
    id newElement = [[templateEl class] new];
    Ivar subtypeIvar = class_getInstanceVariable([templateEl class], "_subtype");
    Ivar itemIvar = class_getInstanceVariable([templateEl class], "_item_menuItem");
    if (!newElement || !subtypeIvar || !itemIvar)
        return orig_prismMenuView_init3(self, _cmd, elements, header, edr);

    ptrdiff_t offset = ivar_getOffset(subtypeIvar);
    *(uint64_t *)((uint8_t *)(__bridge void *)newElement + offset) =
        *(uint64_t *)((uint8_t *)(__bridge void *)templateEl + offset);
    object_setIvar(newElement, itemIvar, menuItem);

    NSMutableArray *newElements = [NSMutableArray arrayWithObject:newElement];
    [newElements addObjectsFromArray:elements];
    return orig_prismMenuView_init3(self, _cmd, newElements, header, edr);
}

%ctor {
    Class prismMenuView = objc_getClass("IGDSPrismMenu.IGDSPrismMenuView");
    if (prismMenuView) {
        SEL sel = @selector(initWithMenuElements:headerText:edrEnabled:);
        if ([prismMenuView instancesRespondToSelector:sel])
            MSHookMessageEx(prismMenuView, sel, (IMP)new_prismMenuView_init3, (IMP *)&orig_prismMenuView_init3);
    }
}
