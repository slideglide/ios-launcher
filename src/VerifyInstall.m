#import "VerifyInstall.h"
#import "GeodeInstaller.h"
#import "Utils.h"
#import "LCUtils/LCAppInfo.h"
#import "LCUtils/LCAppModel.h"
#import "LCUtils/LCUtils.h"
#import "LCUtils/Shared.h"
#import "LCUtils/unarchive.h"
#import <dlfcn.h>
#import <UIKit/UIKit.h>

#import <objc/runtime.h>

typedef void (^DecompressCompletion)(NSError * _Nullable error);

BOOL hasDoneUpdate = NO;

@implementation VerifyInstall 
// for actually knowing whether they own the app!
+ (BOOL)verifyGDAuthenticity {
    return [[Utils getPrefs] boolForKey:@"GDVerified"];
}

+ (BOOL)canLaunchAppWithBundleID:(NSString *)bundleID {
    Class LSApplicationWorkspace_class = objc_getClass("LSApplicationWorkspace");
    if (!LSApplicationWorkspace_class) return NO;
    id workspace = [LSApplicationWorkspace_class performSelector:@selector(defaultWorkspace)];
    if (!workspace) return NO;
    SEL selector = NSSelectorFromString(@"openApplicationWithBundleID:");
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[workspace methodSignatureForSelector:selector]];
    [invocation setTarget:workspace];
    [invocation setSelector:selector];
    [invocation setArgument:&bundleID atIndex:2];

    [invocation invoke];
    //BOOL canLaunch = [workspace performSelector:@selector(openApplicationWithBundleID:) withObject:bundleID];
    [NSThread sleepForTimeInterval:1.0];
    BOOL canLaunch;
    [invocation getReturnValue:&canLaunch];
    return canLaunch;
}

+ (void)startVerifyGDAuth:(RootViewController*)root {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Launch Geometry Dash"
        message:@"This will attempt to open the app. After launching the app to test if you have it installed.\n\nYou will need to manually return to this app to verify that Geometry Dash has been launched."
        preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *launchAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        BOOL canLaunch = [VerifyInstall canLaunchAppWithBundleID:@"com.robtop.geometryjump"];
        if (!canLaunch) {
            UIAlertController *resultAlert = [UIAlertController alertControllerWithTitle:@"Error"
                message:@"Geometry Dash couldn't be launched.\nPlease verify that you have installed the correct Geometry Dash app."
                preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
            [resultAlert addAction:okAction];
            [root presentViewController:resultAlert animated:YES completion:nil];
            return;
        }
        NSUserDefaults *prefs = [Utils getPrefs];
        [prefs setBool:YES forKey:@"UPDATE_AUTOMATICALLY"];
        [prefs setBool:YES forKey:@"GDVerified"];
        [prefs synchronize];
        [root updateState];
    }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:launchAction];
    [alert addAction:cancelAction];
    [root presentViewController:alert animated:YES completion:nil];
}
// after the user installed the patched ipa
+ (BOOL)verifyGDInstalled {
    BOOL res = NO;
    if ([
        [NSFileManager defaultManager] fileExistsAtPath:[[LCPath bundlePath] URLByAppendingPathComponent:[Utils gdBundleName] isDirectory:YES].path isDirectory:&res
    ]) {
        if ([[Utils getPrefs] boolForKey:@"GDNeedsUpdate"]) return NO;
        return res;
    };
    return NO;
}


+ (void)decompress:(NSString*) fileToExtract
    extractionPath:(NSString*)extractionPath
    completion:(DecompressCompletion)completion {
    NSLog(@"Starting decomp of %@ to %@", fileToExtract, extractionPath);
    [[NSFileManager defaultManager] createDirectoryAtPath:extractionPath withIntermediateDirectories:YES attributes:nil error:nil];
    int res = extract(fileToExtract, extractionPath, nil);
    if (res != 0) return completion([NSError errorWithDomain:@"DecompressError" code:res userInfo:nil]);
    return completion(nil);
}

// I CANT (return BOOL instead?)
+ (void)startGDInstall:(RootViewController*)root url:(NSURL*)url {
    @autoreleasepool {
        [[Utils getPrefs] setBool:NO forKey:@"GDNeedsUpdate"];
        //https://github.com/khanhduytran0/LiveContainer/blob/d950e0501944282d757bc5c3b60557d8b64e43c9/LiveContainerSwiftUI/LCAppListView.swift#L348
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtURL:[[LCPath bundlePath] URLByAppendingPathComponent:[Utils gdBundleName]] error:nil];
        [fm createDirectoryAtURL:[LCPath bundlePath] withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *payloadPath = [[fm temporaryDirectory] URLByAppendingPathComponent:@"Payload"];
        NSError *error = nil;
        if ([fm fileExistsAtPath:[payloadPath path]]) {
            [fm removeItemAtURL:payloadPath error:&error];
            if (error) {
                [root updateState];
                // do i .localizedDescription
                return NSLog(@"Error removing item from payload: %@", error);
            }
        }
        /*[fm removeItemAtURL:payloadPath error:&error];
        if (error) {
            return NSLog(@"Error removing item from url: %@", error);
        }*/


        // async bad, i cant even update ui without it.. and it sometimes is unstable too!
        dispatch_async(dispatch_get_main_queue(), ^{
            [root barProgress:0];
            [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer * _Nonnull timer) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (getProgress() < 100) {
                        [root barProgress:getProgress()];
                    } else if (getProgress() >= 100) {
                        [root progressVisibility:YES];
                        [timer invalidate];
                    }
                });
            }];
        });
        [VerifyInstall decompress:url.path extractionPath:[[fm temporaryDirectory] path] completion:^(NSError * _Nullable decompError) {
            if (decompError) {
                [Utils showError:root title:@"Decompressing IPA failed" error:decompError];
                [root updateState];
                return NSLog(@"Error trying to decompress IPA: %@", decompError);
            }
            NSError *error = nil;
            
            NSArray<NSString*>* payloadContents = [fm contentsOfDirectoryAtPath:payloadPath.path error:&error];
            if (error) {
                [Utils showError:root title:@"Retrieving contents failed" error:error];
                [root updateState];
                return NSLog(@"Error retrieving contents of directory: %@", error);
            }
            NSString *appBundleName = nil;
            for (NSString *fileName in payloadContents) {
                if ([fileName hasSuffix:@".app"]) {
                    appBundleName = fileName;
                    break;
                }
            }
            NSURL *appFolderPath = [payloadPath URLByAppendingPathComponent:appBundleName];
            LCAppInfo *newAppInfo = [[LCAppInfo alloc] initWithBundlePath:appFolderPath.path];
            NSString *appRelativePath = [NSString stringWithFormat:@"%@.app", [newAppInfo bundleIdentifier]];
            NSURL *outputFolder = [[LCPath bundlePath] URLByAppendingPathComponent:appRelativePath];
            LCAppModel *appToReplace = nil;
            SharedModel *sharedModel = [[SharedModel alloc] init];

            // sorry i really couldnt figure this out
            NSArray<LCAppModel*>* sameBundleIdApp = [sharedModel.apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(LCAppModel *app, NSDictionary *bindings) {
                return [app.appInfo.bundleIdentifier isEqualToString:newAppInfo.bundleIdentifier];
            }]];

            if (sameBundleIdApp.count == 0) {
                sameBundleIdApp = [sharedModel.hiddenApps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(LCAppModel *app, NSDictionary *bindings) {
                    return [app.appInfo.bundleIdentifier isEqualToString:newAppInfo.bundleIdentifier];
                }]];
                
                // we found a hidden app, we need to authenticate before proceeding
                if (sameBundleIdApp.count > 0 && !sharedModel.isHiddenAppUnlocked) {
                    // im sorry, i know i can do @try but it looks absolutely cursed
                    // also i have no idea how to do this
                    /*BOOL authenticated = [LCUtils authenticateUser:&error];
                    if (!authenticated) {
                        //self.installprogressVisible = NO;
                        return;
                    }*/
                }
            }

            if ([fm fileExistsAtPath:outputFolder.path] || sameBundleIdApp.count > 0) {
                // ah yes, c casting
                appRelativePath = [NSString stringWithFormat:@"%@_%ld.app", [newAppInfo bundleIdentifier], (long)CFAbsoluteTimeGetCurrent()];

                outputFolder = [LCPath.bundlePath URLByAppendingPathComponent:appRelativePath];
                if (![fm removeItemAtURL:outputFolder error:&error]) {
                    NSLog(@"Error removing item: %@", error);
                }
            }
            // Move it!
            [fm moveItemAtURL:appFolderPath toURL:outputFolder error:&error];
            if (error) {
                [Utils showError:root title:@"Moving items failed" error:error];
                [root updateState];
                return NSLog(@"Error moving item from url: %@", error);
            }
            LCAppInfo *finalNewApp = [[LCAppInfo alloc] initWithBundlePath:outputFolder.path];
            if (finalNewApp == nil) {
                [root updateState];
                return NSLog(@"Error getting new app from LCAppInfo");
            }
            finalNewApp.relativeBundlePath = appRelativePath;

            finalNewApp.signer = [[Utils getPrefs] boolForKey:@"USE_ZSIGN"] ? 1 : 0;
            [finalNewApp patchExecAndSignIfNeedWithCompletionHandler:^(BOOL success, NSString *errorInfo) {
                if (![VerifyInstall verifyGeodeInstalled]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        //[root updateState];
                        root.optionalTextLabel.text = @"Downloading Geode...";
                        [[[GeodeInstaller alloc] init] startInstall:root ignoreRoot:NO];
                    });
                }
                if (success) {
                    LCAppModel *newAppModel = [[LCAppModel alloc] initWithAppInfo:finalNewApp delegate:nil];
                    if (appToReplace != nil) {
                        finalNewApp.autoSaveDisabled = true;
                        finalNewApp.isShared = appToReplace.appInfo.isShared;
                        finalNewApp.bypassAssertBarrierOnQueue = appToReplace.appInfo.bypassAssertBarrierOnQueue;
                        finalNewApp.doSymlinkInbox = appToReplace.appInfo.doSymlinkInbox;
                        finalNewApp.containerInfo = appToReplace.appInfo.containerInfo;
                        [finalNewApp setTweakFolder:appToReplace.appInfo.tweakFolder];
                        finalNewApp.signer = appToReplace.appInfo.signer;
                        finalNewApp.selectedLanguage = appToReplace.appInfo.selectedLanguage;
                        finalNewApp.dataUUID = appToReplace.appInfo.dataUUID;
                        finalNewApp.ignoreDlopenError = appToReplace.appInfo.ignoreDlopenError;
                        finalNewApp.autoSaveDisabled = false;

                        [sharedModel.apps removeObject:appToReplace];
                        [sharedModel.apps addObject:newAppModel];
                    } else {
                        [sharedModel.apps addObject:newAppModel];
                    }
                } else {
                    NSLog(@"error with signing? not sure if its really a bad thing: %@", errorInfo);
                    // error, or not? idk, its very vague whether unsigned apps work
                }
            } progressHandler:^(NSProgress *signProgress) {
                //[installProgress addChild:signProgress withPendingUnitCount:20];
            } forceSign:NO];
        }];
    }
}

// after the user installed geode itself
+ (BOOL)verifyGeodeInstalled {
    return [[NSFileManager defaultManager] fileExistsAtPath:[[LCPath tweakPath] URLByAppendingPathComponent:@"Geode.ios.dylib"].path];
}
+ (BOOL)verifyAll {
    if (!hasDoneUpdate && [[Utils getPrefs] boolForKey:@"UPDATE_AUTOMATICALLY"]) {
        hasDoneUpdate = YES;
        return NO;
    }
    return [VerifyInstall verifyGDAuthenticity] && [VerifyInstall verifyGDInstalled] && [VerifyInstall verifyGeodeInstalled];
}
@end
