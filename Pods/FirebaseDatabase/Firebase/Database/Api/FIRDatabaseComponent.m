/*
 * Copyright 2018 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "FIRDatabaseComponent.h"

#import "FIRDatabaseConfig_Private.h"
#import "FIRDatabase_Private.h"
#import "FRepoManager.h"

#import <FirebaseAuthInterop/FIRAuthInterop.h>
#import <FirebaseCore/FIRAppInternal.h>
#import <FirebaseCore/FIRComponent.h>
#import <FirebaseCore/FIRComponentContainer.h>
#import <FirebaseCore/FIRDependency.h>
#import <FirebaseCore/FIRLibrary.h>
#import <FirebaseCore/FIROptions.h>

NS_ASSUME_NONNULL_BEGIN

/** A NSMutableDictionary of FirebaseApp name and FRepoInfo to FirebaseDatabase
 * instance. */
typedef NSMutableDictionary<NSString *, FIRDatabase *> FIRDatabaseDictionary;

@interface FIRDatabaseComponent () <FIRComponentLifecycleMaintainer, FIRLibrary>
@property(nonatomic) FIRDatabaseDictionary *instances;
/// Internal intializer.
- (instancetype)initWithApp:(FIRApp *)app;
@end

@implementation FIRDatabaseComponent

#pragma mark - Initialization

- (instancetype)initWithApp:(FIRApp *)app {
    self = [super init];
    if (self) {
        _app = app;
        _instances = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - Lifecycle

+ (void)load {
    [FIRApp registerInternalLibrary:(Class<FIRLibrary>)self
                           withName:@"fire-db"
                        withVersion:[FIRDatabase sdkVersion]];
}

#pragma mark - FIRComponentRegistrant

+ (NSArray<FIRComponent *> *)componentsToRegister {
    FIRDependency *authDep =
        [FIRDependency dependencyWithProtocol:@protocol(FIRAuthInterop)
                                   isRequired:NO];
    FIRComponentCreationBlock creationBlock =
        ^id _Nullable(FIRComponentContainer *container, BOOL *isCacheable) {
        *isCacheable = YES;
        return [[FIRDatabaseComponent alloc] initWithApp:container.app];
    };
    FIRComponent *databaseProvider =
        [FIRComponent componentWithProtocol:@protocol(FIRDatabaseProvider)
                        instantiationTiming:FIRInstantiationTimingLazy
                               dependencies:@[ authDep ]
                              creationBlock:creationBlock];
    return @[ databaseProvider ];
}

#pragma mark - Instance management.

- (void)appWillBeDeleted:(FIRApp *)app {
    NSString *appName = app.name;
    if (appName == nil) {
        return;
    }
    FIRDatabaseDictionary *instances = [self instances];
    @synchronized(instances) {
        // Clean up the deleted instance in an effort to remove any resources
        // still in use. Note: Any leftover instances of this exact database
        // will be invalid.
        for (FIRDatabase *database in [instances allValues]) {
            [FRepoManager disposeRepos:database.config];
        }
        [instances removeAllObjects];
    }
}

#pragma mark - FIRDatabaseProvider Conformance

- (FIRDatabase *)databaseForApp:(FIRApp *)app URL:(NSString *)url {
    if (app == nil) {
        [NSException raise:@"InvalidFIRApp"
                    format:@"nil FIRApp instance passed to databaseForApp."];
    }

    if (url == nil) {
        [NSException raise:@"MissingDatabaseURL"
                    format:@"Failed to get FirebaseDatabase instance: "
                            "Specify DatabaseURL within FIRApp or from your "
                            "databaseForApp:URL: call."];
    }

    NSURL *databaseUrl = [NSURL URLWithString:url];

    if (databaseUrl == nil) {
        [NSException raise:@"InvalidDatabaseURL"
                    format:@"The Database URL '%@' cannot be parsed. "
                            "Specify a valid DatabaseURL within FIRApp or from "
                            "your databaseForApp:URL: call.",
                           databaseUrl];
    } else if (![databaseUrl.path isEqualToString:@""] &&
               ![databaseUrl.path isEqualToString:@"/"]) {
        [NSException
             raise:@"InvalidDatabaseURL"
            format:@"Configured Database URL '%@' is invalid. It should point "
                    "to the root of a Firebase Database but it includes a "
                    "path: %@",
                   databaseUrl, databaseUrl.path];
    }

    FIRDatabaseDictionary *instances = [self instances];
    @synchronized(instances) {
        FParsedUrl *parsedUrl =
            [FUtilities parseUrl:databaseUrl.absoluteString];
        NSString *urlIndex =
            [NSString stringWithFormat:@"%@:%@", parsedUrl.repoInfo.host,
                                       [parsedUrl.path toString]];
        FIRDatabase *database = instances[urlIndex];
        if (!database) {
            id<FAuthTokenProvider> authTokenProvider = [FAuthTokenProvider
                authTokenProviderWithAuth:FIR_COMPONENT(FIRAuthInterop,
                                                        app.container)];

            // If this is the default app, don't set the session persistence key
            // so that we use our default ("default") instead of the FIRApp
            // default ("[DEFAULT]") so that we preserve the default location
            // used by the legacy Firebase SDK.
            NSString *sessionIdentifier = @"default";
            if (![FIRApp isDefaultAppConfigured] ||
                app != [FIRApp defaultApp]) {
                sessionIdentifier = app.name;
            }

            FIRDatabaseConfig *config = [[FIRDatabaseConfig alloc]
                initWithSessionIdentifier:sessionIdentifier
                        authTokenProvider:authTokenProvider];
            database = [[FIRDatabase alloc] initWithApp:app
                                               repoInfo:parsedUrl.repoInfo
                                                 config:config];
            instances[urlIndex] = database;
        }

        return database;
    }
}

@end

NS_ASSUME_NONNULL_END
