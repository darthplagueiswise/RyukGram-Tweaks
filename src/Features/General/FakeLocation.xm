// Fake location — overrides CLLocationManager so any IG location read returns our coord.

#import "../../Utils.h"
#import <CoreLocation/CoreLocation.h>
#import <objc/message.h>

static BOOL sciFakeLocOn(void) {
    return [SCIUtils getBoolPref:@"fake_location_enabled"];
}

static CLLocation *sciFakeLocation(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    double lat = [[d objectForKey:@"fake_location_lat"] doubleValue];
    double lon = [[d objectForKey:@"fake_location_lon"] doubleValue];
    return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)
                                         altitude:35
                               horizontalAccuracy:5
                                 verticalAccuracy:5
                                        timestamp:[NSDate date]];
}

static void sciFeedFake(CLLocationManager *mgr) {
    id<CLLocationManagerDelegate> d = mgr.delegate;
    if (![d respondsToSelector:@selector(locationManager:didUpdateLocations:)]) return;
    CLLocation *loc = sciFakeLocation();
    NSArray *locs = @[ loc ];
    dispatch_async(dispatch_get_main_queue(), ^{
        [d locationManager:mgr didUpdateLocations:locs];
    });
}

%hook CLLocationManager

- (CLLocation *)location {
    if (sciFakeLocOn()) return sciFakeLocation();
    return %orig;
}

- (void)startUpdatingLocation {
    %orig;
    if (sciFakeLocOn()) sciFeedFake(self);
}

- (void)requestLocation {
    if (sciFakeLocOn()) { sciFeedFake(self); return; }
    %orig;
}

%end
