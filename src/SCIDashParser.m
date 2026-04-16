#import "SCIDashParser.h"
#import <objc/runtime.h>
#import <objc/message.h>

@implementation SCIDashRepresentation
@end

static id sciDashFieldCache(id obj, NSString *key) {
    if (!obj || !key) return nil;
    static Ivar fcIvar = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class c = NSClassFromString(@"IGAPIStorableObject");
        if (c) fcIvar = class_getInstanceVariable(c, "_fieldCache");
    });
    if (!fcIvar) return nil;
    id fc = nil;
    @try { fc = object_getIvar(obj, fcIvar); } @catch (__unused id e) { return nil; }
    if (![fc isKindOfClass:[NSDictionary class]]) return nil;
    id val = ((NSDictionary *)fc)[key];
    if (!val || [val isKindOfClass:[NSNull class]]) return nil;
    return val;
}

@implementation SCIDashParser

+ (NSString *)dashManifestForMedia:(id)media {
    if (!media) return nil;

    NSArray *keys = @[@"video_dash_manifest", @"dash_manifest",
                      @"video_dash_manifest_url", @"dash_manifest_url"];

    for (NSString *key in keys) {
        id val = sciDashFieldCache(media, key);
        if ([val isKindOfClass:[NSString class]] && [(NSString *)val length] > 10)
            return val;
    }

    id video = nil;
    SEL videoSel = @selector(video);
    if ([media respondsToSelector:videoSel]) {
        video = ((id(*)(id, SEL))objc_msgSend)(media, videoSel);
        if (video && ![(id)video isKindOfClass:[NSObject class]]) video = nil;
    }
    if (video) {
        for (NSString *key in keys) {
            id val = sciDashFieldCache(video, key);
            if ([val isKindOfClass:[NSString class]] && [(NSString *)val length] > 10)
                return val;
        }
    }

    return nil;
}

+ (NSArray<SCIDashRepresentation *> *)parseManifest:(NSString *)xmlString {
    if (!xmlString.length) return @[];

    NSMutableArray<SCIDashRepresentation *> *results = [NSMutableArray array];

    NSError *err = nil;

    // AdaptationSet blocks (handles both contentType= and mimeType= patterns)
    NSRegularExpression *adaptRE = [NSRegularExpression
        regularExpressionWithPattern:@"(<AdaptationSet[^>]*>)(.*?)</AdaptationSet>"
        options:NSRegularExpressionDotMatchesLineSeparators error:&err];
    if (err) return @[];

    NSRegularExpression *ctRE = [NSRegularExpression
        regularExpressionWithPattern:@"contentType=\"(video|audio)\"" options:NSRegularExpressionCaseInsensitive error:nil];
    NSRegularExpression *mtRE = [NSRegularExpression
        regularExpressionWithPattern:@"mimeType=\"(video|audio)/[^\"]*\"" options:NSRegularExpressionCaseInsensitive error:nil];

    NSRegularExpression *repRE = [NSRegularExpression
        regularExpressionWithPattern:@"<Representation[^>]*>"
        options:0 error:nil];

    NSRegularExpression *baseURLRE = [NSRegularExpression
        regularExpressionWithPattern:@"<BaseURL>(.*?)</BaseURL>"
        options:0 error:nil];

    NSRegularExpression *bwRE = [NSRegularExpression
        regularExpressionWithPattern:@"bandwidth=\"(\\d+)\"" options:0 error:nil];
    NSRegularExpression *widthRE = [NSRegularExpression
        regularExpressionWithPattern:@"(?:^|\\s)width=\"(\\d+)\"" options:0 error:nil];
    NSRegularExpression *heightRE = [NSRegularExpression
        regularExpressionWithPattern:@"(?:^|\\s)height=\"(\\d+)\"" options:0 error:nil];
    NSRegularExpression *labelRE = [NSRegularExpression
        regularExpressionWithPattern:@"FBQualityLabel=\"([^\"]+)\"" options:0 error:nil];
    NSRegularExpression *fpsRE = [NSRegularExpression
        regularExpressionWithPattern:@"frameRate=\"([0-9./]+)\"" options:0 error:nil];
    NSRegularExpression *codecsRE = [NSRegularExpression
        regularExpressionWithPattern:@"codecs=\"([^\"]+)\"" options:0 error:nil];

    [adaptRE enumerateMatchesInString:xmlString options:0
        range:NSMakeRange(0, xmlString.length)
        usingBlock:^(NSTextCheckingResult *adaptMatch, __unused NSMatchingFlags flags, __unused BOOL *stop) {

        NSString *adaptTag = [xmlString substringWithRange:[adaptMatch rangeAtIndex:1]];
        NSString *adaptBody = [xmlString substringWithRange:[adaptMatch rangeAtIndex:2]];

        NSString *contentType = nil;
        NSTextCheckingResult *ctMatch = [ctRE firstMatchInString:adaptTag options:0
            range:NSMakeRange(0, adaptTag.length)];
        if (ctMatch) {
            contentType = [[adaptTag substringWithRange:[ctMatch rangeAtIndex:1]] lowercaseString];
        } else {
            NSTextCheckingResult *mtMatch = [mtRE firstMatchInString:adaptTag options:0
                range:NSMakeRange(0, adaptTag.length)];
            if (mtMatch) {
                contentType = [[adaptTag substringWithRange:[mtMatch rangeAtIndex:1]] lowercaseString];
            }
        }
        if (!contentType) return;

        NSArray<NSTextCheckingResult *> *repMatches =
            [repRE matchesInString:adaptBody options:0 range:NSMakeRange(0, adaptBody.length)];
        NSArray<NSTextCheckingResult *> *urlMatches =
            [baseURLRE matchesInString:adaptBody options:0 range:NSMakeRange(0, adaptBody.length)];

        for (NSUInteger i = 0; i < repMatches.count && i < urlMatches.count; i++) {
            NSString *repTag = [adaptBody substringWithRange:repMatches[i].range];
            NSString *baseURL = [adaptBody substringWithRange:[urlMatches[i] rangeAtIndex:1]];

            if (!baseURL.length) continue;

            baseURL = [baseURL stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];

            SCIDashRepresentation *rep = [SCIDashRepresentation new];
            rep.url = [NSURL URLWithString:baseURL];
            rep.contentType = contentType;

            NSTextCheckingResult *bwMatch = [bwRE firstMatchInString:repTag options:0
                range:NSMakeRange(0, repTag.length)];
            if (bwMatch) rep.bandwidth = [[repTag substringWithRange:[bwMatch rangeAtIndex:1]] integerValue];

            NSTextCheckingResult *wMatch = [widthRE firstMatchInString:repTag options:0
                range:NSMakeRange(0, repTag.length)];
            if (wMatch) rep.width = [[repTag substringWithRange:[wMatch rangeAtIndex:1]] integerValue];

            NSTextCheckingResult *hMatch = [heightRE firstMatchInString:repTag options:0
                range:NSMakeRange(0, repTag.length)];
            if (hMatch) rep.height = [[repTag substringWithRange:[hMatch rangeAtIndex:1]] integerValue];

            NSTextCheckingResult *fpsMatch = [fpsRE firstMatchInString:repTag options:0
                range:NSMakeRange(0, repTag.length)];
            if (fpsMatch) {
                NSString *raw = [repTag substringWithRange:[fpsMatch rangeAtIndex:1]];
                NSArray *parts = [raw componentsSeparatedByString:@"/"];
                if (parts.count == 2) {
                    float num = [parts[0] floatValue], den = [parts[1] floatValue];
                    if (den > 0) rep.frameRate = num / den;
                } else {
                    rep.frameRate = [raw floatValue];
                }
            }
            NSTextCheckingResult *codecsMatch = [codecsRE firstMatchInString:repTag options:0
                range:NSMakeRange(0, repTag.length)];
            if (codecsMatch) rep.codecs = [repTag substringWithRange:[codecsMatch rangeAtIndex:1]];

            // Quality label from shorter dimension (1080x1920 → "1080p")
            if (rep.width > 0 && rep.height > 0) {
                NSInteger shortSide = MIN(rep.width, rep.height);
                rep.qualityLabel = [NSString stringWithFormat:@"%ldp", (long)shortSide];
            } else if (rep.height > 0) {
                rep.qualityLabel = [NSString stringWithFormat:@"%ldp", (long)rep.height];
            } else {
                NSTextCheckingResult *lMatch = [labelRE firstMatchInString:repTag options:0
                    range:NSMakeRange(0, repTag.length)];
                if (lMatch) rep.qualityLabel = [repTag substringWithRange:[lMatch rangeAtIndex:1]];
            }

            if (rep.url) [results addObject:rep];
        }
    }];

    return [results copy];
}

+ (SCIDashRepresentation *)bestVideoFromRepresentations:(NSArray<SCIDashRepresentation *> *)reps {
    return [[self videoRepresentations:reps] firstObject];
}

+ (SCIDashRepresentation *)bestAudioFromRepresentations:(NSArray<SCIDashRepresentation *> *)reps {
    SCIDashRepresentation *best = nil;
    for (SCIDashRepresentation *r in reps) {
        if (![r.contentType isEqualToString:@"audio"]) continue;
        if (!best || r.bandwidth > best.bandwidth) best = r;
    }
    return best;
}

+ (NSArray<SCIDashRepresentation *> *)videoRepresentations:(NSArray<SCIDashRepresentation *> *)reps {
    NSMutableArray *videos = [NSMutableArray array];
    for (SCIDashRepresentation *r in reps) {
        if ([r.contentType isEqualToString:@"video"]) [videos addObject:r];
    }
    return [videos sortedArrayUsingComparator:^NSComparisonResult(SCIDashRepresentation *a, SCIDashRepresentation *b) {
        return [@(b.bandwidth) compare:@(a.bandwidth)]; // descending
    }];
}

+ (SCIDashRepresentation *)representationForQuality:(SCIVideoQuality)quality
                                fromRepresentations:(NSArray<SCIDashRepresentation *> *)reps {
    NSArray *sorted = [self videoRepresentations:reps];
    if (!sorted.count) return nil;

    switch (quality) {
        case SCIVideoQualityHighest: return sorted.firstObject;
        case SCIVideoQualityLowest: return sorted.lastObject;
        case SCIVideoQualityMedium: return sorted[sorted.count / 2];
        case SCIVideoQualityAsk: return sorted.firstObject; // caller handles the picker
    }
    return sorted.firstObject;
}

@end
