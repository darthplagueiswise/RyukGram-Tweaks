// Saves to a dedicated "RyukGram" album in the Photos library.
// Creates the album on first use. All RyukGram-initiated saves should go
// through here so the user can find their downloads in one place.
#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

@interface SCIPhotoAlbum : NSObject

// Album name shown in the user's Photos app.
+ (NSString *)albumName;

// Asynchronously fetches (or creates on first use) the RyukGram album.
+ (void)fetchOrCreateAlbumWithCompletion:(void (^)(PHAssetCollection *album, NSError *error))completion;

// Saves a file at fileURL into the RyukGram album. The file is treated as a
// photo or video based on its extension. Calls completion on the main queue.
+ (void)saveFileToAlbum:(NSURL *)fileURL completion:(void (^)(BOOL success, NSError *error))completion;

// Watches the photo library for the next asset insertion and moves it into
// the RyukGram album. Used to capture saves performed via UIActivityViewController's
// "Save to Photos" activity, which we don't initiate ourselves.
//
// The watcher auto-unregisters after the first capture or after a timeout.
+ (void)watchForNextSavedAsset;

@end
