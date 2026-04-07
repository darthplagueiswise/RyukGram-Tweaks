#import "../../Utils.h"
#import "../../InstagramHeaders.h"

// Defined in SeenButtons.x
extern __weak IGDirectThreadViewController *sciActiveThreadVC;
extern BOOL sciAutoTypingEnabled(void);
extern void sciDoAutoSeen(IGDirectThreadViewController *threadVC);

%hook IGDirectTypingStatusService
- (void)updateOutgoingStatusIsActive:(_Bool)active threadKey:(id)key threadMetadata:(id)metadata typingStatusType:(long long)type {
    // Mark the visible thread as seen on the first typing event — runs even
    // when typing-status broadcasting is blocked below.
    if (active && sciAutoTypingEnabled()) {
        IGDirectThreadViewController *vc = sciActiveThreadVC;
        if (vc) sciDoAutoSeen(vc);
    }

    if ([SCIUtils getBoolPref:@"disable_typing_status"]) return;

    return %orig(active, key, metadata, type);
}
%end