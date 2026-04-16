#import "SCIFakeLocationPickerVC.h"
#import <MapKit/MapKit.h>
#import "../Localization/SCILocalization.h"

#pragma mark - Search results

@interface SCIFakeLocationSearchResultsVC : UITableViewController <MKLocalSearchCompleterDelegate>
@property (nonatomic, strong) MKLocalSearchCompleter *completer;
@property (nonatomic, copy) NSArray<MKLocalSearchCompletion *> *results;
@property (nonatomic, copy) void (^onSelect)(MKLocalSearchCompletion *completion);
@property (nonatomic, assign) MKCoordinateRegion region;
@end

@implementation SCIFakeLocationSearchResultsVC

- (instancetype)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.completer = [MKLocalSearchCompleter new];
        self.completer.delegate = self;
        self.results = @[];
    }
    return self;
}

- (void)setRegion:(MKCoordinateRegion)region {
    _region = region;
    if (CLLocationCoordinate2DIsValid(region.center)) self.completer.region = region;
}

- (void)setQuery:(NSString *)q {
    if (!q.length) { self.results = @[]; [self.tableView reloadData]; return; }
    self.completer.queryFragment = q;
}

- (void)completerDidUpdateResults:(MKLocalSearchCompleter *)c {
    self.results = c.results;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.results.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"r"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"r"];
    MKLocalSearchCompletion *r = self.results[ip.row];
    cell.textLabel.text = r.title;
    cell.detailTextLabel.text = r.subtitle;
    cell.imageView.image = [UIImage systemImageNamed:@"mappin.circle"];
    cell.imageView.tintColor = [UIColor systemRedColor];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (self.onSelect) self.onSelect(self.results[ip.row]);
}

@end

#pragma mark - Picker

@interface SCIFakeLocationPickerVC () <MKMapViewDelegate, UISearchResultsUpdating, UISearchControllerDelegate, CLLocationManagerDelegate>
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) MKPointAnnotation *pin;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) SCIFakeLocationSearchResultsVC *resultsVC;
@property (nonatomic, strong) UIButton *locateButton;
@property (nonatomic, strong) UIVisualEffectView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *useButton;
@property (nonatomic, copy) NSString *resolvedName;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, assign) BOOL didRequestAuth;
@end

@implementation SCIFakeLocationPickerVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = self.titleText.length ? self.titleText : SCILocalized(@"Pick location");

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];

    self.locationManager = [CLLocationManager new];
    self.locationManager.delegate = self;

    [self setupMap];
    [self setupSearch];
    [self setupLocateButton];
    [self setupCard];

    CLLocationCoordinate2D coord = CLLocationCoordinate2DIsValid(self.initialCoord)
        ? self.initialCoord : CLLocationCoordinate2DMake(48.8584, 2.2945);
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(coord, 1500, 1500) animated:NO];
    self.resultsVC.region = self.mapView.region;

    if (CLLocationCoordinate2DIsValid(self.initialCoord)) {
        [self dropPinAt:self.initialCoord name:nil reverseGeocode:YES];
    }
}

#pragma mark - Setup

- (void)setupMap {
    self.mapView = [[MKMapView alloc] initWithFrame:self.view.bounds];
    self.mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.mapView.delegate = self;
    self.mapView.showsUserLocation = YES;
    self.mapView.showsCompass = YES;
    [self.view addSubview:self.mapView];

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(onLongPress:)];
    lp.minimumPressDuration = 0.35;
    [self.mapView addGestureRecognizer:lp];
}

- (void)setupSearch {
    self.resultsVC = [SCIFakeLocationSearchResultsVC new];
    __weak typeof(self) weakSelf = self;
    self.resultsVC.onSelect = ^(MKLocalSearchCompletion *r) { [weakSelf performSearchForCompletion:r]; };

    UISearchController *sc = [[UISearchController alloc] initWithSearchResultsController:self.resultsVC];
    sc.searchResultsUpdater = self;
    sc.delegate = self;
    sc.obscuresBackgroundDuringPresentation = YES;
    sc.searchBar.placeholder = SCILocalized(@"Search address or place");
    self.navigationItem.searchController = sc;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    self.searchController = sc;
}

- (void)setupLocateButton {
    self.locateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.locateButton.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.locateButton.tintColor = [UIColor systemBlueColor];
    [self.locateButton setImage:[UIImage systemImageNamed:@"location"] forState:UIControlStateNormal];
    self.locateButton.layer.cornerRadius = 8;
    self.locateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.locateButton addTarget:self action:@selector(onLocateTap) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.locateButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.locateButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [self.locateButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-140],
        [self.locateButton.widthAnchor constraintEqualToConstant:40],
        [self.locateButton.heightAnchor constraintEqualToConstant:40],
    ]];
}

- (void)onLocateTap {
    CLAuthorizationStatus status = self.locationManager.authorizationStatus;
    if (status == kCLAuthorizationStatusNotDetermined) {
        self.didRequestAuth = YES;
        [self.locationManager requestWhenInUseAuthorization];
        return;
    }
    if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        [self showLocationDeniedAlert];
        return;
    }
    if (!CLLocationManager.locationServicesEnabled) {
        [self showServicesDisabledAlert];
        return;
    }
    self.mapView.showsUserLocation = YES;
    self.mapView.userTrackingMode = MKUserTrackingModeFollow;
    CLLocation *loc = self.mapView.userLocation.location ?: self.locationManager.location;
    if (loc) {
        [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(loc.coordinate, 800, 800) animated:YES];
    }
}

- (void)showLocationDeniedAlert {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:SCILocalized(@"Location access denied")
                                                               message:SCILocalized(@"Enable Location Services for Instagram in Settings to use your current location.")
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Open Settings") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)showServicesDisabledAlert {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:SCILocalized(@"Location Services off")
                                                               message:SCILocalized(@"Turn Location Services on in Settings → Privacy to use your current location.")
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    CLAuthorizationStatus s = manager.authorizationStatus;
    if (!self.didRequestAuth) return;
    self.didRequestAuth = NO;
    if (s == kCLAuthorizationStatusAuthorizedWhenInUse || s == kCLAuthorizationStatusAuthorizedAlways) {
        [self onLocateTap];
    } else if (s == kCLAuthorizationStatusDenied || s == kCLAuthorizationStatusRestricted) {
        [self showLocationDeniedAlert];
    }
}

- (void)setupCard {
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial];
    self.cardView = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.cardView.layer.cornerRadius = 16;
    self.cardView.layer.cornerCurve = kCACornerCurveContinuous;
    self.cardView.clipsToBounds = YES;
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardView.hidden = YES;
    [self.view addSubview:self.cardView];

    self.titleLabel = [UILabel new];
    self.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.subtitleLabel = [UILabel new];
    self.subtitleLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.subtitleLabel.textColor = [UIColor secondaryLabelColor];
    self.subtitleLabel.numberOfLines = 1;
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.useButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.useButton setTitle:SCILocalized(@"Use this location") forState:UIControlStateNormal];
    self.useButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.useButton.backgroundColor = [UIColor systemBlueColor];
    [self.useButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.useButton.layer.cornerRadius = 12;
    self.useButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.useButton addTarget:self action:@selector(commit) forControlEvents:UIControlEventTouchUpInside];

    UIView *content = self.cardView.contentView;
    [content addSubview:self.titleLabel];
    [content addSubview:self.subtitleLabel];
    [content addSubview:self.useButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.cardView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12],
        [self.cardView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [self.cardView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],

        [self.titleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:14],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:2],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],

        [self.useButton.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:12],
        [self.useButton.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [self.useButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [self.useButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-12],
        [self.useButton.heightAnchor constraintEqualToConstant:46],
    ]];
}

#pragma mark - Pin

- (void)onLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    CGPoint p = [g locationInView:self.mapView];
    CLLocationCoordinate2D c = [self.mapView convertPoint:p toCoordinateFromView:self.mapView];
    [self dropPinAt:c name:nil reverseGeocode:YES];
}

- (void)dropPinAt:(CLLocationCoordinate2D)coord name:(NSString *)name reverseGeocode:(BOOL)resolve {
    if (self.pin) [self.mapView removeAnnotation:self.pin];
    self.pin = [MKPointAnnotation new];
    self.pin.coordinate = coord;
    self.pin.title = name;
    [self.mapView addAnnotation:self.pin];
    [self.mapView selectAnnotation:self.pin animated:YES];
    self.resolvedName = name;
    [self updateCard];

    if (resolve && !name.length) {
        CLLocation *loc = [[CLLocation alloc] initWithLatitude:coord.latitude longitude:coord.longitude];
        CLGeocoder *g = [CLGeocoder new];
        [g reverseGeocodeLocation:loc completionHandler:^(NSArray<CLPlacemark *> *pm, NSError *err) {
            if (err || !pm.count) return;
            CLPlacemark *p = pm.firstObject;
            NSString *resolved = p.name ?: p.locality ?: p.country;
            if (!resolved.length) return;
            if (!self.pin ||
                fabs(self.pin.coordinate.latitude - coord.latitude) > 0.0001 ||
                fabs(self.pin.coordinate.longitude - coord.longitude) > 0.0001) return;
            self.resolvedName = resolved;
            self.pin.title = resolved;
            [self updateCard];
        }];
    }
}

- (void)updateCard {
    if (!self.pin) { self.cardView.hidden = YES; return; }
    self.cardView.hidden = NO;
    CLLocationCoordinate2D c = self.pin.coordinate;
    self.titleLabel.text = self.resolvedName.length ? self.resolvedName : SCILocalized(@"Dropped pin");
    self.subtitleLabel.text = [NSString stringWithFormat:@"%.5f, %.5f", c.latitude, c.longitude];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    self.resultsVC.region = self.mapView.region;
    [self.resultsVC setQuery:sc.searchBar.text];
}

- (void)performSearchForCompletion:(MKLocalSearchCompletion *)completion {
    MKLocalSearchRequest *req = [[MKLocalSearchRequest alloc] initWithCompletion:completion];
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:req];
    [search startWithCompletionHandler:^(MKLocalSearchResponse *resp, NSError *err) {
        if (err || !resp.mapItems.count) return;
        MKMapItem *item = resp.mapItems.firstObject;
        CLLocationCoordinate2D c = item.placemark.coordinate;
        NSString *name = item.name ?: completion.title;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.searchController setActive:NO];
            [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(c, 1500, 1500) animated:YES];
            [self dropPinAt:c name:name reverseGeocode:NO];
        });
    }];
}

#pragma mark - Map delegate (draggable pin)

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:[MKUserLocation class]]) return nil;
    static NSString *kID = @"scipin";
    MKMarkerAnnotationView *v = (MKMarkerAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:kID];
    if (!v) {
        v = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:kID];
    } else {
        v.annotation = annotation;
    }
    v.draggable = YES;
    v.canShowCallout = YES;
    v.markerTintColor = [UIColor systemRedColor];
    v.animatesWhenAdded = YES;
    return v;
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view
    didChangeDragState:(MKAnnotationViewDragState)newState fromOldState:(MKAnnotationViewDragState)oldState {
    if (newState == MKAnnotationViewDragStateEnding) {
        view.dragState = MKAnnotationViewDragStateNone;
        CLLocationCoordinate2D c = view.annotation.coordinate;
        self.resolvedName = nil;
        [self updateCard];
        CLLocation *loc = [[CLLocation alloc] initWithLatitude:c.latitude longitude:c.longitude];
        [[CLGeocoder new] reverseGeocodeLocation:loc completionHandler:^(NSArray<CLPlacemark *> *pm, NSError *err) {
            if (err || !pm.count || !self.pin) return;
            if (fabs(self.pin.coordinate.latitude - c.latitude) > 0.0001 ||
                fabs(self.pin.coordinate.longitude - c.longitude) > 0.0001) return;
            CLPlacemark *p = pm.firstObject;
            NSString *name = p.name ?: p.locality ?: p.country;
            if (!name.length) return;
            self.resolvedName = name;
            self.pin.title = name;
            [self updateCard];
        }];
    }
}

#pragma mark - Actions

- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)commit {
    if (!self.pin) return;
    CLLocationCoordinate2D c = self.pin.coordinate;
    NSString *name = self.resolvedName.length ? self.resolvedName
        : [NSString stringWithFormat:@"%.4f, %.4f", c.latitude, c.longitude];
    void (^cb)(double, double, NSString *) = self.onPick;
    [self dismissViewControllerAnimated:YES completion:^{
        if (cb) cb(c.latitude, c.longitude, name);
    }];
}

@end
