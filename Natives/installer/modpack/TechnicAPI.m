#import "TechnicAPI.h"
#import "MinecraftResourceDownloadTask.h"
#import "PLProfiles.h"
// #import "UnzipKit.h" // Not needed for Technic Solder
// #import "ModpackUtils.h" // Not needed for Technic Solder

// Ensure API_SOURCE_TECHNIC is defined somewhere accessible, e.g., in ModpackAPI.h
// #define API_SOURCE_TECHNIC 2

@implementation TechnicAPI

- (instancetype)init {
    return [super initWithURL:@"https://solder.technicpack.net/api"];
}

- (NSMutableArray *)searchModWithFilters:(NSDictionary<NSString *, NSString *> *)searchFilters previousPageResult:(NSMutableArray *)technicSearchResult {
    // ... (No change from previous version) ...
    NSDictionary *response = [self getEndpoint:@"modpack" params:nil];
    if (!response) {
        return nil;
    }

    NSMutableArray *result = technicSearchResult ?: [NSMutableArray new];
    NSArray *modpackSlugs = response[@"modpacks"];

    for (NSString *slug in modpackSlugs) {
        NSDictionary *modpackDetails = [self getEndpoint:[NSString stringWithFormat:@"modpack/%@", slug] params:nil];
        if (modpackDetails) {
            NSString *searchQuery = searchFilters[@"name"];
            if (searchQuery.length > 0 && ![modpackDetails[@"name"] localizedCaseInsensitiveContainsString:searchQuery]) {
                continue;
            }

            BOOL isModpack = YES;
            NSString *imageUrl = @"https://cdn.technicpack.net/platform2/logos/technic-logo.png"; // Placeholder

            [result addObject:@{
                @"apiSource": @(API_SOURCE_TECHNIC),
                @"isModpack": @(isModpack),
                @"id": modpackDetails[@"slug"],
                @"title": modpackDetails[@"name"],
                @"description": modpackDetails[@"url"] ?: @"",
                @"imageUrl": imageUrl
            }.mutableCopy];
        }
    }
    self.reachedLastPage = YES;
    return result;
}

- (void)loadDetailsOfMod:(NSMutableDictionary *)item {
    // ... (No change from previous version) ...
    NSString *modpackSlug = item[@"id"];
    NSDictionary *modpackDetails = [self getEndpoint:[NSString stringWithFormat:@"modpack/%@", modpackSlug] params:nil];
    if (!modpackDetails) {
        return;
    }

    NSArray<NSString *> *versionNames = [modpackDetails[@"builds"] allKeys];
    versionNames = [versionNames sortedArrayUsingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
        return [obj2 compare:obj1 options:NSNumericSearch];
    }];

    NSMutableArray<NSString *> *mcVersionNames = [NSMutableArray new];
    NSMutableArray<NSString *> *urls = [NSMutableArray new];
    NSMutableArray<NSString *> *hashes = [NSMutableArray new];
    NSMutableArray<NSString *> *sizes = [NSMutableArray new];
    NSMutableArray<NSDictionary *> *buildDetails = [NSMutableArray new];

    for (NSString *version in versionNames) {
        NSDictionary *build = [self getEndpoint:[NSString stringWithFormat:@"modpack/%@/%@", modpackSlug, version] params:nil];
        if (build) {
            [mcVersionNames addObject:build[@"minecraft"] ?: [NSNull null]];
            [urls addObject:[NSNull null]];
            [hashes addObject:[NSNull null]];
            [sizes addObject:[NSNull null]];
            [buildDetails addObject:build];
        }
    }

    item[@"versionNames"] = versionNames;
    item[@"mcVersionNames"] = mcVersionNames;
    item[@"versionSizes"] = sizes;
    item[@"versionUrls"] = urls;
    item[@"versionHashes"] = hashes;
    item[@"technicBuildDetails"] = buildDetails;
    item[@"versionDetailsLoaded"] = @(YES);
}

- (void)downloader:(MinecraftResourceDownloadTask *)downloader submitDownloadTasksFromPackage:(NSString *)packagePath toPath:(NSString *)destPath {
    // The `detail` and `selectedVersionIndex` from `downloadModpackFromAPI`
    // are accessible within the `downloader` instance here.
    NSDictionary *modDetail = downloader.metadata; // Assuming `metadata` holds the original `detail` dictionary
    NSUInteger selectedVersionIndex = [[modDetail objectForKey:@"selectedVersionIndex"] unsignedIntegerValue]; // Or however you pass this

    if (modDetail[@"technicBuildDetails"] == nil || selectedVersionIndex >= [modDetail[@"technicBuildDetails"] count]) {
        [downloader finishDownloadWithErrorString:@"Technic build details not found or invalid version selected."];
        return;
    }

    NSDictionary *selectedBuild = modDetail[@"technicBuildDetails"][selectedVersionIndex];

    NSArray *mods = selectedBuild[@"mods"];
    if (!mods || [mods count] == 0) {
        [downloader finishDownloadWithErrorString:@"No mods found in the selected Technic build. Cannot install."];
        return;
    }

    downloader.progress.totalUnitCount = [mods count];

    NSString *modsPath = [destPath stringByAppendingPathComponent:@"mods"];
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:modsPath withIntermediateDirectories:YES attributes:nil error:&error]) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to create mods directory: %@", error.localizedDescription]];
        return;
    }

    for (NSDictionary *mod in mods) {
        NSString *url = mod[@"url"];
        NSString *md5Hash = mod[@"md5"];
        NSString *fileName = [url lastPathComponent];

        if (!url) {
            NSLog(@"Warning: Technic mod entry missing URL: %@", mod);
            downloader.progress.completedUnitCount++;
            continue;
        }

        NSString *filePath = [modsPath stringByAppendingPathComponent:fileName];
        NSUInteger size = 0; // Technic Solder usually doesn't provide file sizes directly

        NSURLSessionDownloadTask *task = [downloader createDownloadTask:url size:size sha:md5Hash altName:nil toPath:filePath];
        if (task) {
            [downloader.fileList addObject:filePath];
            [task resume];
        } else if (!downloader.progress.cancelled) {
            downloader.progress.completedUnitCount++;
        } else {
            return;
        }
    }

    if (packagePath.length > 0) {
        [NSFileManager.defaultManager removeItemAtPath:packagePath error:nil];
    }

    // --- Minecraft Client Version and Profile Creation ---
    NSString *mcVersion = selectedBuild[@"minecraft"];
    if (mcVersion.length > 0) {
        // Here's where you need to call your Minecraft client installation logic.
        // Assuming your app has a way to get the 'main' Minecraft client JSON for a version
        // and its JAR, etc. This is *not* part of PLProfiles directly based on its header.
        // You would typically have a separate manager class for Minecraft core versions.
        // Example (pseudo-code, you'll need to implement this part if you don't have it):
        // [[MinecraftVersionManager sharedManager] installVersion:mcVersion completion:^(NSError *mcError) {
        //     if (mcError) {
        //         [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to install Minecraft version %@: %@", mcVersion, mcError.localizedDescription]];
        //     } else {
        //         // Continue with profile creation if MC client is installed
        //     }
        // }];
        // For now, we proceed assuming MC client is either already present or will be handled elsewhere.
    }

    // Create a new profile for the modpack
    NSString *modpackName = selectedBuild[@"modpack"];
    NSString *base64IconString = @"";

    // Attempt to load the icon from modpackDetails if available from the search phase
    if (modDetail[@"imageUrl"]) { // Use `modDetail` here
        NSURL *iconURL = [NSURL URLWithString:modDetail[@"imageUrl"]];
        NSData *iconData = [NSData dataWithContentsOfURL:iconURL];
        if (iconData) {
            base64IconString = [NSString stringWithFormat:@"data:image/png;base64,%@", [iconData base64EncodedStringWithOptions:0]];
        }
    }

    PLProfiles.current.profiles[modpackName] = @{
        @"gameDir": [NSString stringWithFormat:@"./custom_gamedir/%@", destPath.lastPathComponent],
        @"name": modpackName,
        @"lastVersionId": mcVersion,
        @"icon": base64IconString
    }.mutableCopy;
    PLProfiles.current.selectedProfileName = modpackName;

    // Finally, save the profiles
    [PLProfiles.current save];
}

@end
