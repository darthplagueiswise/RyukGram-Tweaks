// Send files in DMs — adds a "Send File" option to the plus menu.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL sciFileMenuPending = NO;
static __weak UIViewController *sciFileThreadVC = nil;

@interface _SCIFilePickerDelegate : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, weak) UIViewController *threadVC;
@end

static _SCIFilePickerDelegate *sciFilePickerDelegate = nil;

@implementation _SCIFilePickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url || !self.threadVC) return;

    id msgSenderFC = nil;
    @try { msgSenderFC = [self.threadVC valueForKey:@"messageSenderFeatureController"]; } @catch (__unused id e) {}
    if (!msgSenderFC) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Message sender not found")]; return; }

    id sender = nil;
    @try { sender = [msgSenderFC valueForKey:@"messageSender"]; } @catch (__unused id e) {}
    if (!sender) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Send service not found")]; return; }

    SEL sendSel = NSSelectorFromString(@"sendFileWithURL:threadKey:attribution:replyMessagePk:quotedPublishedMessage:messageSentSpeedLogger:messageSentSpeedMarker:localSendSpeedLogger:localSendSpeedMarker:");
    if (![sender respondsToSelector:sendSel]) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"File sending not supported")]; return; }

    id threadKey = nil;
    @try { threadKey = [self.threadVC valueForKey:@"threadKey"]; } @catch (__unused id e) {}
    if (!threadKey) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No thread key")]; return; }

    typedef void (*SendFn)(id, SEL, id, id, id, id, id, id, id, id, id);
    ((SendFn)objc_msgSend)(sender, sendSel, url, threadKey, nil, nil, nil, nil, nil, nil, nil);
}

@end

static void sciShowFilePicker(UIViewController *threadVC) {
    sciFilePickerDelegate = [_SCIFilePickerDelegate new];
    sciFilePickerDelegate.threadVC = threadVC;

    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.data"] inMode:UIDocumentPickerModeImport];
    picker.delegate = sciFilePickerDelegate;
    picker.allowsMultipleSelection = NO;
    [threadVC presentViewController:picker animated:YES completion:nil];
}

// MARK: - Plus menu injection

%hook IGDSMenu

- (id)initWithMenuItems:(NSArray *)items edr:(BOOL)edr headerLabelText:(id)header {
    if (![SCIUtils getBoolPref:@"send_file"] || !sciFileMenuPending) return %orig;
    sciFileMenuPending = NO;

    for (id item in items) {
        if ([item respondsToSelector:@selector(title)]) {
            id title = [item valueForKey:@"title"];
            if ([title isKindOfClass:[NSString class]] && [title isEqualToString:@"Send File"]) return %orig;
        }
    }

    Class itemClass = NSClassFromString(@"IGDSMenuItem");
    if (!itemClass) return %orig;

    UIImage *img = [[UIImage systemImageNamed:@"doc"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    void (^handler)(void) = ^{
        if (sciFileThreadVC) sciShowFilePicker(sciFileThreadVC);
    };

    SEL initSel = @selector(initWithTitle:image:handler:);
    if (![itemClass instancesRespondToSelector:initSel]) return %orig;

    typedef id (*InitFn)(id, SEL, id, id, id);
    id fileItem = ((InitFn)objc_msgSend)([itemClass alloc], initSel, @"Send File", img, handler);
    if (!fileItem) return %orig;

    NSMutableArray *newItems = [NSMutableArray arrayWithObject:fileItem];
    [newItems addObjectsFromArray:items];
    return %orig(newItems, edr, header);
}

%end

// MARK: - Thread VC hook

%hook IGDirectThreadViewController

- (void)composerOverflowButtonMenuWillPrepareExpandWithPlusButton:(id)plusButton {
    %orig;
    if (![SCIUtils getBoolPref:@"send_file"]) return;
    sciFileThreadVC = self;
    sciFileMenuPending = YES;
}

%end
