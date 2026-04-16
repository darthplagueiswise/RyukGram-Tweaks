// SCIQualityPicker — quality selection bottom sheet for HD downloads.

#import <UIKit/UIKit.h>
#import "SCIDashParser.h"

@interface SCIQualityPicker : NSObject

/// Show quality picker or auto-pick based on prefs. Returns NO if
/// enhanced downloads are off or no DASH manifest found (calls fallback).
+ (BOOL)pickQualityForMedia:(id)media
                   fromView:(UIView *)sourceView
                     picked:(void(^)(SCIDashRepresentation *video, SCIDashRepresentation *audio))picked
                   fallback:(void(^)(void))fallback;

@end
