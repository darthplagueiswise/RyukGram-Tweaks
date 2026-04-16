// Map picker — long-press to drop a draggable pin, search suggestions via MKLocalSearchCompleter.

#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>

@interface SCIFakeLocationPickerVC : UIViewController

@property (nonatomic, copy) void (^onPick)(double lat, double lon, NSString *name);
@property (nonatomic, assign) CLLocationCoordinate2D initialCoord;
@property (nonatomic, copy) NSString *titleText;

@end
