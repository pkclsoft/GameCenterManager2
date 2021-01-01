//
//  GameCenterManager.m
//
//  Created by Nihal Ahmed on 12-03-16. Updated by iRare Media on 5-27-13.
//  Copyright (c) 2012 NABZ Software. All rights reserved.
//

// GameCenterManager uses ARC, check for compatibility before building
#if !__has_feature(objc_arc)
#error GameCenterManager uses Objective-C ARC. Compile these files with ARC enabled. Add the -fobjc-arc compiler flag to enable ARC for only these files.
#endif

#import "GameCenterManager.h"
#import "SDCloudUserDefaults.h"

//------------------------------------------------------------------------------------------------------------//
//------- GameCenter Manager Singleton -----------------------------------------------------------------------//
//------------------------------------------------------------------------------------------------------------//
#pragma mark GameCenter Manager

#define IS_IOS_8_OR_LATER    ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0)

@interface GameCenterManager () {
    NSMutableArray *GCMLeaderboards;
    
#if TARGET_OS_IPHONE
    UIBackgroundTaskIdentifier backgroundProcess;
#endif
}

#if SUPPORT_ENCRYPTION
@property (nonatomic, assign, readwrite) BOOL shouldCryptData;
@property (nonatomic, strong, readwrite) NSString *cryptKey;
@property (nonatomic, strong, readwrite) NSData *cryptKeyData;
#endif
@property (nonatomic, assign, readwrite) GameCenterAvailability previousGameCenterAvailability;

@end

@implementation GameCenterManager

#pragma mark - Object Lifecycle

+ (GameCenterManager *)sharedManager {
    static GameCenterManager *singleton;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        singleton = [[self alloc] init];
    });
    
    return singleton;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        BOOL gameCenterAvailable = [self checkGameCenterAvailability];
        
        [USERDEFAULTS synchronize];
        
        if ([USERDEFAULTS objectForKey:@"scoresSynced"] == nil) {
            NSLog(@"scoresSynced not setup");
            [USERDEFAULTS setBool:NO forKey:[@"scoresSynced" stringByAppendingString:[self localPlayerID]]];
        } else {
            NSLog(@"scoresSynced WAS setup");
        }
        
        if ([USERDEFAULTS objectForKey:@"achievementsSynced"] == nil) {
            NSLog(@"achievementsSynced not setup");
             [USERDEFAULTS setBool:NO forKey:[@"achievementsSynced" stringByAppendingString:[self localPlayerID]]];
        } else {
            NSLog(@"achievementsSynced WAS setup");
        }
        
        [USERDEFAULTS synchronize];
        
        if (gameCenterAvailable) {
            // Set GameCenter as available
            [self setIsGameCenterAvailable:YES];

            if (![USERDEFAULTS boolForKey:[@"scoresSynced" stringByAppendingString:[self localPlayerID]]]
                || ![USERDEFAULTS boolForKey:[@"achievementsSynced" stringByAppendingString:[self localPlayerID]]])
                [self syncGameCenter];
            else
                [self reportSavedScoresAndAchievements];
        } else {
            [self setIsGameCenterAvailable:NO];
        }
    }
    
    return self;
}

//------------------------------------------------------------------------------------------------------------//
//------- GameCenter Manager Setup ---------------------------------------------------------------------------//
//------------------------------------------------------------------------------------------------------------//
#pragma mark - GameCenter Manager Setup

- (void)setupManager {
    // This code should only be called once, to avoid unhandled exceptions when parsing the PLIST data
}

#if SUPPORT_ENCRYPTION
- (void)setupManagerAndSetShouldCryptWithKey:(NSString *)cryptionKey {
    // This code should only be called once, to avoid unhandled exceptions when parsing the PLIST data
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        self.shouldCryptData = YES;
        self.cryptKey = cryptionKey;
        self.cryptKeyData = [cryptionKey dataUsingEncoding:NSUTF8StringEncoding];
    });
}
#endif

#if TARGET_OS_IOS || TARGET_OS_TV
- (void) reportPlayerNotSignedIn:(UIViewController*)viewController
#else
- (void) reportPlayerNotSignedIn:(NSViewController*)viewController
#endif
{
    if ([self previousGameCenterAvailability] != GameCenterAvailabilityNoPlayer) {
        [self setPreviousGameCenterAvailability:GameCenterAvailabilityNoPlayer];
        NSDictionary *errorDictionary = @{@"message": @"Player is not yet signed into GameCenter. Please prompt the player using the authenticateUser delegate method.", @"title": @"No Player"};
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([[self delegate] respondsToSelector:@selector(gameCenterManager:availabilityChanged:)])
                [[self delegate] gameCenterManager:self availabilityChanged:errorDictionary];
            
            if ([[self delegate] respondsToSelector:@selector(gameCenterManager:authenticateUser:)]) {
                [[self delegate] gameCenterManager:self authenticateUser:viewController];
            } else {
                NSLog(@"[ERROR] %@ Fails to Respond to the required delegate method gameCenterManager:authenticateUser:. This delegate method must be properly implemented to use GC Manager", [self delegate]);
            }
        });
    }
}

- (BOOL)checkGameCenterAvailability {
    BOOL isGameCenterAPIAvailable = (NSClassFromString(@"GKLocalPlayer")) != nil;
    
    if (!isGameCenterAPIAvailable) {
        if ([self previousGameCenterAvailability] != GameCenterAvailabilityNotAvailable) {
            [self setPreviousGameCenterAvailability:GameCenterAvailabilityNotAvailable];
            NSDictionary *errorDictionary = @{@"message": @"GameKit Framework not available on this device. GameKit is only available on devices with iOS 4.1 or higher. Some devices running iOS 4.1 may not have GameCenter enabled.", @"title": @"GameCenter Unavailable"};
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([[self delegate] respondsToSelector:@selector(gameCenterManager:availabilityChanged:)])
                    [[self delegate] gameCenterManager:self availabilityChanged:errorDictionary];
            });
        }
        
        return NO;
        
    } else {
        // The GameKit Framework is available. Now check if an internet connection can be established
        BOOL internetAvailable = [self isInternetAvailable];
        if (!internetAvailable) {
            if ([self previousGameCenterAvailability] != GameCenterAvailabilityNoInternet) {
                [self setPreviousGameCenterAvailability:GameCenterAvailabilityNoInternet];
                NSDictionary *errorDictionary = @{@"message": @"Cannot connect to the internet. Connect to the internet to establish a connection with GameCenter. Achievements and scores will still be saved locally and then uploaded later.", @"title": @"Internet Unavailable"};
            
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([[self delegate] respondsToSelector:@selector(gameCenterManager:availabilityChanged:)])
                        [[self delegate] gameCenterManager:self availabilityChanged:errorDictionary];
                });
            }
            
            return NO;
            
        } else {
            // The internet is available and the current device is connected. Now check if the player is authenticated
            GKLocalPlayer *localPlayer = [GKLocalPlayer localPlayer];
#if TARGET_OS_IOS || TARGET_OS_TV
            localPlayer.authenticateHandler = ^(UIViewController *viewController, NSError *error) {
                if (viewController != nil) {
                    [self reportPlayerNotSignedIn:viewController];
                } else if (!error) {
                    // Authentication handler completed successfully. Re-check availability
                    [self checkGameCenterAvailability];
                }
            };
#else
            localPlayer.authenticateHandler = ^(NSViewController *viewController, NSError *error) {
                if (viewController != nil) {
                    [self reportPlayerNotSignedIn:viewController];
                } else if (!error) {
                    // Authentication handler completed successfully. Re-check availability
                    [self checkGameCenterAvailability];
                }
            };
#endif
            
            if (![[GKLocalPlayer localPlayer] isAuthenticated]) {
                if ([self previousGameCenterAvailability] != GameCenterAvailabilityPlayerNotAuthenticated) {
                    [self setPreviousGameCenterAvailability:GameCenterAvailabilityPlayerNotAuthenticated];
                    NSDictionary *errorDictionary = @{@"message": @"Player is not signed into GameCenter, has declined to sign into GameCenter, or GameKit had an issue validating this game / app.", @"title": @"Player not Authenticated"};
                
                    if ([[self delegate] respondsToSelector:@selector(gameCenterManager:availabilityChanged:)])
                        [[self delegate] gameCenterManager:self availabilityChanged:errorDictionary];
                }
                
                return NO;
                
            } else {
                if ([self previousGameCenterAvailability] != GameCenterAvailabilityPlayerAuthenticated) {
                    [self setPreviousGameCenterAvailability:GameCenterAvailabilityPlayerAuthenticated];
                    // The current player is logged into GameCenter
                    NSDictionary *successDictionary = [NSDictionary dictionaryWithObject:@"GameCenter Available" forKey:@"status"];
                    [USERDEFAULTS setBool:NO forKey:[@"scoresSynced" stringByAppendingString:[self localPlayerID]]];
                    [USERDEFAULTS setBool:NO forKey:[@"achievementsSynced" stringByAppendingString:[self localPlayerID]]];
                    [USERDEFAULTS synchronize];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([[self delegate] respondsToSelector:@selector(gameCenterManager:availabilityChanged:)])
                            [[self delegate] gameCenterManager:self availabilityChanged:successDictionary];
                    });
                    
                    self.isGameCenterAvailable = YES;
                }
                
                return YES;
            }
        }
    }
}

// Check for internet with Reachability
- (BOOL)isInternetAvailable {
    Reachability *reachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus internetStatus = [reachability currentReachabilityStatus];
    
    if (internetStatus == NotReachable) {
        NSLog(@"Internet unavailable");
        NSError *error = [NSError errorWithDomain:[NSString stringWithFormat:@"Internet unavailable - could not connect to the internet. Connect to WiFi or a Cellular Network to upload data to GameCenter."] code:GCMErrorInternetNotAvailable userInfo:nil];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([[self delegate] respondsToSelector:@selector(gameCenterManager:error:)])
                [[self delegate] gameCenterManager:self error:error];
        });
        
        return NO;
    } else {
        return YES;
    }
}

//------------------------------------------------------------------------------------------------------------//
//------- GameCenter Syncing ---------------------------------------------------------------------------------//
//------------------------------------------------------------------------------------------------------------//
#pragma mark - GameCenter Syncing

- (NSString*) savedScoresKey {
    return [NSString stringWithFormat:@"%@_savedScores", [self localPlayerID]];
}

- (void) storePlayerData:(id)obj withKey:(NSString*)key {
    NSData *saveData;
#if SUPPORT_ENCRYPTION
    if (self.shouldCryptData == YES) {
        saveData = [[NSKeyedArchiver archivedDataWithRootObject:obj] encryptedWithKey:self.cryptKeyData];
    } else {
#endif
        saveData = [NSKeyedArchiver archivedDataWithRootObject:obj requiringSecureCoding:NO error:nil];
#if SUPPORT_ENCRYPTION
    }
#endif
    [USERDEFAULTS setObject:saveData forKey:key];
    [USERDEFAULTS synchronize];
}

- (id) getPlayerDataOfClass:(Class)cls withKey:(NSString*)key {
    NSData *gameCenterManagerData;
#if SUPPORT_ENCRYPTION
    if (self.shouldCryptData == YES) {
        gameCenterManagerData = [((NSData*)[USERDEFAULTS objectForKey:key]) decryptedWithKey:self.cryptKeyData];
    } else {
#endif
        gameCenterManagerData = ((NSData*)[USERDEFAULTS objectForKey:key]);
#if SUPPORT_ENCRYPTION
    }
#endif
    
    return [NSKeyedUnarchiver unarchivedObjectOfClass:cls fromData:gameCenterManagerData error:nil];
}

- (void)syncGameCenter {
#if TARGET_OS_IPHONE || TARGET_OS_TV
    // Begin Syncing with GameCenter
    
    // Ensure the task isn't interrupted even if the user exits the app
    backgroundProcess = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        //End the Background Process
        [[UIApplication sharedApplication] endBackgroundTask:self->backgroundProcess];
        self->backgroundProcess = UIBackgroundTaskInvalid;
    }];
    
    // Move the process to the background thread to avoid clogging up the UI
    dispatch_queue_t syncGameCenterOnBackgroundThread = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
    dispatch_async(syncGameCenterOnBackgroundThread, ^{
        
        // Check if GameCenter is available
        if ([self checkGameCenterAvailability] == YES) {
            // Check if Leaderboard Scores are synced
            if (![USERDEFAULTS boolForKey:[@"scoresSynced" stringByAppendingString:[self localPlayerID]]]) {
                if (self->GCMLeaderboards == nil) {
                    [GKLeaderboard loadLeaderboardsWithCompletionHandler:^(NSArray *leaderboards, NSError *error) {
                        if (error == nil) {
                            self->GCMLeaderboards = [[NSMutableArray alloc] initWithArray:leaderboards];
                            [self syncGameCenter];
                        } else {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                if ([[self delegate] respondsToSelector:@selector(gameCenterManager:error:)])
                                    [[self delegate] gameCenterManager:self error:error];
                            });
                        }
                    }];
                    return;
                }
                
                
				if (self->GCMLeaderboards.count > 0) {

                    GKLeaderboard *leaderboardRequest = [[GKLeaderboard alloc] initWithPlayers:[NSArray arrayWithObject:[GKLocalPlayer localPlayer]]];
                    [leaderboardRequest setIdentifier:[(GKLeaderboard *)[self->GCMLeaderboards objectAtIndex:0] identifier]];
                    
                    [leaderboardRequest loadScoresWithCompletionHandler:^(NSArray *scores, NSError *error) {
                        if (error == nil) {
                            if (scores.count > 0) {
                                NSMutableDictionary *playerDict = [self getPlayerDataOfClass:[NSMutableDictionary class] withKey:[self localPlayerID]];
                                
                                if (playerDict == nil) {
                                    playerDict = [NSMutableDictionary dictionary];
                                }
                                
                                float savedHighScoreValue = 0;
                                NSNumber *savedHighScore = [playerDict objectForKey:leaderboardRequest.localPlayerScore.leaderboardIdentifier];
                                
                                if (savedHighScore != nil) {
                                    savedHighScoreValue = [savedHighScore longLongValue];
                                }
                                
                                [playerDict setObject:[NSNumber numberWithLongLong:MAX(leaderboardRequest.localPlayerScore.value, savedHighScoreValue)] forKey:leaderboardRequest.localPlayerScore.leaderboardIdentifier];
                                
                                [self storePlayerData:playerDict withKey:[self localPlayerID]];
                            }
                            
                            // Seeing an NSRangeException for an empty array when trying to remove the object
                            // Despite the check above in this scope that leaderboards count is > 0
                            if (self->GCMLeaderboards.count > 0) {
                                [self->GCMLeaderboards removeObjectAtIndex:0];
                            }
                            
                            [self syncGameCenter];
                        } else {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                if ([[self delegate] respondsToSelector:@selector(gameCenterManager:error:)])
                                    [[self delegate] gameCenterManager:self error:error];
                            });
                        }
                    }];
                } else {
                    [USERDEFAULTS setBool:YES forKey:[@"scoresSynced" stringByAppendingString:[self localPlayerID]]];
                    [self syncGameCenter];
                }
                
                
                // Check if Achievements are synced
            } else if (![USERDEFAULTS boolForKey:[@"achievementsSynced" stringByAppendingString:[self localPlayerID]]]) {
                [GKAchievement loadAchievementsWithCompletionHandler:^(NSArray *achievements, NSError *error) {
                    if (error == nil) {
                        NSLog(@"Number of Achievements: %@", achievements);
                        if (achievements.count > 0) {
                            NSMutableDictionary *playerDict = [self getPlayerDataOfClass:[NSMutableDictionary class] withKey:[self localPlayerID]];

                            if (playerDict == nil) {
                                playerDict = [NSMutableDictionary dictionary];
                            }
                            
                            for (GKAchievement *achievement in achievements) {
                                [playerDict setObject:[NSNumber numberWithDouble:achievement.percentComplete] forKey:achievement.identifier];
                            }

                            [self storePlayerData:playerDict withKey:[self localPlayerID]];
                        }
                        
                        [USERDEFAULTS setBool:YES forKey:[@"achievementsSynced" stringByAppendingString:[self localPlayerID]]];
                        [self syncGameCenter];
                    } else {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if ([[self delegate] respondsToSelector:@selector(gameCenterManager:error:)])
                                [[self delegate] gameCenterManager:self error:error];
                        });
                    }
                }];
            } else if( [USERDEFAULTS boolForKey:[@"achievementsSynced" stringByAppendingString:[self localPlayerID]]] == YES &&
                      [USERDEFAULTS boolForKey:[@"scoresSynced" stringByAppendingString:[self localPlayerID]]] == YES ) {
                // Game Center Synced
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([[self delegate] respondsToSelector:@selector(gameCenterManager:gameCenterSynced:)]) {
                        [[self delegate] gameCenterManager:self gameCenterSynced:YES];
                    }
                });
            }
            
        } else {
            NSError *error = [NSError errorWithDomain:[NSString stringWithFormat:@"GameCenter unavailable."] code:GCMErrorNotAvailable userInfo:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([[self delegate] respondsToSelector:@selector(gameCenterManager:error:)])
                    [[self delegate] gameCenterManager:self error:error];
            });
        }
    });
    
    // End the Background Process
    [[UIApplication sharedApplication] endBackgroundTask:backgroundProcess];
    backgroundProcess = UIBackgroundTaskInvalid;
#else
    // Check if GameCenter is available
    if ([self checkGameCenterAvailability] == YES) {
        // Check if Leaderboard Scores are synced
        if (![USERDEFAULTS boolForKey:[@"scoresSynced" stringByAppendingString:[self localPlayerID]]]) {
            if (GCMLeaderboards == nil) {
                [GKLeaderboard loadLeaderboardsWithCompletionHandler:^(NSArray *leaderboards, NSError *error) {
                    if (error == nil) {
                        self->GCMLeaderboards = [[NSMutableArray alloc] initWithArray:leaderboards];
                        [self syncGameCenter];
                    } else {
                        NSLog(@"%@",[error localizedDescription]);
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if ([[self delegate] respondsToSelector:@selector(gameCenterManager:error:)])
                                [[self delegate] gameCenterManager:self error:error];
                        });
                    }
                }];
                return;
            }
            
            if (GCMLeaderboards.count > 0) {
#ifdef __MAC_10_10
				GKLeaderboard *leaderboardRequest = [[GKLeaderboard alloc] initWithPlayers:[NSArray arrayWithObject:[GKLocalPlayer localPlayer]]];
				[leaderboardRequest setIdentifier:[(GKLeaderboard *)[GCMLeaderboards objectAtIndex:0] identifier]];
#else
				GKLeaderboard *leaderboardRequest = [[GKLeaderboard alloc] initWithPlayerIDs:[NSArray arrayWithObject:[self localPlayerID]]];
				[leaderboardRequest setCategory:[(GKLeaderboard *)[GCMLeaderboards objectAtIndex:0] category]];
#endif
                [leaderboardRequest loadScoresWithCompletionHandler:^(NSArray *scores, NSError *error) {
                    if (error == nil) {
                        if (scores.count > 0) {
                            NSMutableDictionary *playerDict = [self getPlayerDataOfClass:[NSMutableDictionary class] withKey:[self localPlayerID]];
                            
                            if (playerDict == nil) {
                                playerDict = [NSMutableDictionary dictionary];
                            }
                            
							float savedHighScoreValue = 0;
#ifdef __MAC_10_10
							NSNumber *savedHighScore = [playerDict objectForKey:leaderboardRequest.localPlayerScore.leaderboardIdentifier];
#else
							NSNumber *savedHighScore = [playerDict objectForKey:leaderboardRequest.localPlayerScore.category];
#endif
							
                            if (savedHighScore != nil) {
                                savedHighScoreValue = [savedHighScore longLongValue];
                            }
							
#ifdef __MAC_10_10
							[playerDict setObject:[NSNumber numberWithLongLong:MAX(leaderboardRequest.localPlayerScore.value, savedHighScoreValue)] forKey:leaderboardRequest.localPlayerScore.leaderboardIdentifier];
#else
							[playerDict setObject:[NSNumber numberWithLongLong:MAX(leaderboardRequest.localPlayerScore.value, savedHighScoreValue)] forKey:leaderboardRequest.localPlayerScore.category];
#endif
                            [self storePlayerData:playerDict withKey:[self localPlayerID]];
                        }
                        
                        // Seeing an NSRangeException for an empty array when trying to remove the object
                        // Despite the check above in this scope that leaderboards count is > 0
                        if (self->GCMLeaderboards.count > 0) {
                            [self->GCMLeaderboards removeObjectAtIndex:0];
                        }
                        
                        [self syncGameCenter];
                    } else {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            NSLog(@"%@",[error localizedDescription]);
                            if ([[self delegate] respondsToSelector:@selector(gameCenterManager:error:)])
                                [[self delegate] gameCenterManager:self error:error];
                        });
                    }
                }];
            } else {
                [USERDEFAULTS setBool:YES forKey:[@"scoresSynced" stringByAppendingString:[self localPlayerID]]];
                [self syncGameCenter];
            }
            
            // Check if Achievements are synced
        } else if (![USERDEFAULTS boolForKey:[@"achievementsSynced" stringByAppendingString:[self localPlayerID]]]) {
            [GKAchievement loadAchievementsWithCompletionHandler:^(NSArray *achievements, NSError *error) {
                if (error == nil) {
                    if (achievements.count > 0) {
                        NSMutableDictionary *playerDict = [self getPlayerDataOfClass:[NSMutableDictionary class] withKey:[self localPlayerID]];
                        
                        if (playerDict == nil) {
                            playerDict = [NSMutableDictionary dictionary];
                        }
                        
                        for (GKAchievement *achievement in achievements) {
                            [playerDict setObject:[NSNumber numberWithDouble:achievement.percentComplete] forKey:achievement.identifier];
                        }

                        [self storePlayerData:playerDict withKey:[self localPlayerID]];
                    }
                    
                    [USERDEFAULTS setBool:YES forKey:[@"achievementsSynced" stringByAppendingString:[self localPlayerID]]];
                    [self syncGameCenter];
                } else {
                    NSLog(@"%@",[error localizedDescription]);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([[self delegate] respondsToSelector:@selector(gameCenterManager:error:)])
                            [[self delegate] gameCenterManager:self error:error];
                    });
                }
            }];
        } else if( [USERDEFAULTS boolForKey:[@"achievementsSynced" stringByAppendingString:[self localPlayerID]]] == YES &&
                 [USERDEFAULTS boolForKey:[@"scoresSynced" stringByAppendingString:[self localPlayerID]]] == YES ) {
            // Game Center Synced
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([[self delegate] respondsToSelector:@selector(gameCenterManager:gameCenterSynced:)]) {
                    [[self delegate] gameCenterManager:self gameCenterSynced:YES];
                }
            });
        } else {
        }
    } else {
        NSError *error = [NSError errorWithDomain:[NSString stringWithFormat:@"GameCenter unavailable."] code:GCMErrorNotAvailable userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([[self delegate] respondsToSelector:@selector(gameCenterManager:error:)])
                [[self delegate] gameCenterManager:self error:error];
        });
    }
#endif
}

- (void)reportSavedScoresAndAchievements {
    if ([self isInternetAvailable] == NO) return;
    
    GKScore *gkScore = nil;
    NSMutableArray *savedScores = [self getPlayerDataOfClass:[NSMutableArray class] withKey:[self savedScoresKey]];
    
    if (savedScores != nil) {
        if (savedScores.count > 0) {
            gkScore = [NSKeyedUnarchiver unarchivedObjectOfClass:[GKScore class] fromData:[savedScores objectAtIndex:0] error:nil];
            
            [savedScores removeObjectAtIndex:0];

            [self storePlayerData:savedScores withKey:[self savedScoresKey]];
        }
    }
    
    if (gkScore != nil && gkScore.value != 0) {
        [GKScore reportScores:@[gkScore] withCompletionHandler:^(NSError *error) {
            if (error == nil) {
                [self reportSavedScoresAndAchievements];
            } else {
                [self saveScoreToReportLater:gkScore];
            }
        }];
    } else {
        if ([GKLocalPlayer localPlayer].authenticated) {
            NSString *identifier = nil;
            double percentComplete = 0;
            
            NSMutableDictionary *playerDict = [self getPlayerDataOfClass:[NSMutableDictionary class] withKey:[self localPlayerID]];
                        
            if (playerDict != nil) {
                NSMutableDictionary *savedAchievements = [[playerDict objectForKey:@"SavedAchievements"] mutableCopy];
                if (savedAchievements != nil) {
                    if (savedAchievements.count > 0) {
                        identifier = [[savedAchievements allKeys] objectAtIndex:0];
                        percentComplete = [[savedAchievements objectForKey:identifier] doubleValue];
                        
                        [savedAchievements removeObjectForKey:identifier];
                        [playerDict setObject:savedAchievements forKey:@"SavedAchievements"];
                        
                        [self storePlayerData:playerDict withKey:[self localPlayerID]];
                    }
                }
            }
            
            if (identifier != nil) {
                GKAchievement *achievement = [[GKAchievement alloc] initWithIdentifier:identifier];
                achievement.percentComplete = percentComplete;
                [GKAchievement reportAchievements:@[achievement] withCompletionHandler:^(NSError *error) {
                    if (error == nil) {
                        [self reportSavedScoresAndAchievements];
                    } else {
                        [self saveAchievementToReportLater:achievement.identifier percentComplete:achievement.percentComplete];
                    }
                }];
            }
        }
    }
}


//------------------------------------------------------------------------------------------------------------//
//------- Score and Achievement Reporting --------------------------------------------------------------------//
//------------------------------------------------------------------------------------------------------------//
#pragma mark - Score and Achievement Reporting

- (void)saveAndReportScore:(long long)score leaderboard:(NSString *)identifier sortOrder:(GameCenterSortOrder)order  {
    
    NSMutableDictionary *playerDict = [self getPlayerDataOfClass:[NSMutableDictionary class] withKey:[self localPlayerID]];
    
    if (playerDict == nil) {
        playerDict = [NSMutableDictionary dictionary];
    }
    
    NSNumber *savedHighScore = [playerDict objectForKey:identifier];
    if (savedHighScore == nil) {
        if (order == GameCenterSortOrderHighToLow) {
            savedHighScore = [NSNumber numberWithLongLong:0];
        } else {
            savedHighScore = [NSNumber numberWithLongLong:LONG_LONG_MAX];
        }
    }
    
    long long savedHighScoreValue = [savedHighScore longLongValue];
    
    // Determine if the new score is better than the old score
    BOOL isScoreBetter = NO;
    switch (order) {
        case GameCenterSortOrderLowToHigh: // A lower score is better
            if (score < savedHighScoreValue) {
                isScoreBetter = YES;
            }
            break;
        default:
            if (score > savedHighScoreValue) { // A higher score is better
                isScoreBetter = YES;
            }
            break;
    }
    
    if (isScoreBetter) {
        [playerDict setObject:[NSNumber numberWithLongLong:score] forKey:identifier];
        
        [self storePlayerData:playerDict withKey:[self localPlayerID]];
    }
    
    if ([self checkGameCenterAvailability] == YES) {
		GKScore *gkScore = [[GKScore alloc] initWithLeaderboardIdentifier:identifier];
        [gkScore setValue:score];
        
        [GKScore reportScores:@[gkScore] withCompletionHandler:^(NSError *error) {
            NSDictionary *dict = nil;
            
            if (error == nil) {
                dict = [NSDictionary dictionaryWithObjects:@[gkScore] forKeys:@[@"score"]];
            } else {
                dict = [NSDictionary dictionaryWithObjects:@[error.localizedDescription, gkScore] forKeys:@[@"error", @"score"]];
                [self saveScoreToReportLater:gkScore];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([[self delegate] respondsToSelector:@selector(gameCenterManager:reportedScore:withError:)]) {
                    [[self delegate] gameCenterManager:self reportedScore:gkScore withError:error];
                }
            });
        }];
    } else {
        GKScore *gkScore = [[GKScore alloc] initWithLeaderboardIdentifier:identifier];
        [gkScore setValue:score];
        [self saveScoreToReportLater:gkScore];
    }
}

- (void)saveAndReportAchievement:(NSString *)identifier percentComplete:(double)percentComplete shouldDisplayNotification:(BOOL)displayNotification {
    NSMutableDictionary *playerDict = [self getPlayerDataOfClass:[NSMutableDictionary class] withKey:[self localPlayerID]];
    
    if (playerDict == nil) {
        playerDict = [NSMutableDictionary dictionary];
    }
    
    NSNumber *savedPercentComplete = [playerDict objectForKey:identifier];
    if (savedPercentComplete == nil) {
        savedPercentComplete = [NSNumber numberWithDouble:0];
    }
    
    double savedPercentCompleteValue = [savedPercentComplete doubleValue];
    
    if (percentComplete > savedPercentCompleteValue) {
        [playerDict setObject:[NSNumber numberWithDouble:percentComplete] forKey:identifier];
        
        [self storePlayerData:playerDict withKey:[self localPlayerID]];
    }
    
    if ([self checkGameCenterAvailability] == YES) {
        GKAchievement *achievement = [[GKAchievement alloc] initWithIdentifier:identifier];
        achievement.percentComplete = percentComplete;
        
        if (displayNotification == YES) {
            achievement.showsCompletionBanner = YES;
        } else {
            achievement.showsCompletionBanner = NO;
        }
        
        [GKAchievement reportAchievements:@[achievement] withCompletionHandler:^(NSError *error) {
            NSDictionary *dict = nil;
            
            if (error == nil) {
                dict = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:achievement, nil] forKeys:[NSArray arrayWithObjects:@"achievement", nil]];
            } else {
                if (achievement) {
                    dict = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:error.localizedDescription, achievement, nil] forKeys:[NSArray arrayWithObjects:@"error", @"achievement", nil]];
                }
                
                [self saveAchievementToReportLater:identifier percentComplete:percentComplete];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([[self delegate] respondsToSelector:@selector(gameCenterManager:reportedAchievement:withError:)]) {
                    [[self delegate] gameCenterManager:self reportedAchievement:achievement withError:error];
                }
            });
            
        }];
    } else {
        [self saveAchievementToReportLater:identifier percentComplete:percentComplete];
    }
}

- (void)saveScoreToReportLater:(GKScore *)score {
    if(score.value == 0) {
        return;
    }
    NSData *scoreData = [NSKeyedArchiver archivedDataWithRootObject:score requiringSecureCoding:NO error:nil];
    NSMutableArray *savedScores = [self getPlayerDataOfClass:[NSMutableArray class] withKey:[self savedScoresKey]];
    
    if (savedScores != nil) {
        [savedScores addObject:scoreData];
    } else {
        savedScores = [NSMutableArray arrayWithObject:scoreData];
    }

    [self storePlayerData:savedScores withKey:[self savedScoresKey]];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([[self delegate] respondsToSelector:@selector(gameCenterManager:didSaveScore:)]) {
            [[self delegate] gameCenterManager:self didSaveScore:score];
        }
    });
}

- (void)saveAchievementToReportLater:(NSString *)identifier percentComplete:(double)percentComplete {
    NSMutableDictionary *playerDict = [self getPlayerDataOfClass:[NSMutableDictionary class] withKey:[self localPlayerID]];
    
    if (playerDict != nil) {
        NSMutableDictionary *savedAchievements = [[playerDict objectForKey:@"SavedAchievements"] mutableCopy];
        if (savedAchievements != nil) {
            double savedPercentCompleteValue = 0;
            NSNumber *savedPercentComplete = [savedAchievements objectForKey:identifier];
            
            if (savedPercentComplete != nil) {
                savedPercentCompleteValue = [savedPercentComplete doubleValue];
            }
            
            // Compare the saved percent and the percent that was just submitted, if the submitted percent is greater save it
            if (percentComplete > savedPercentCompleteValue) {
                savedPercentComplete = [NSNumber numberWithDouble:percentComplete];
                [savedAchievements setObject:savedPercentComplete forKey:identifier];
            }
        } else {
            savedAchievements = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithDouble:percentComplete], identifier, nil];
            [playerDict setObject:savedAchievements forKey:@"SavedAchievements"];
        }
    } else {
        NSMutableDictionary *savedAchievements = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithDouble:percentComplete], identifier, nil];
        playerDict = [NSMutableDictionary dictionaryWithObjectsAndKeys:savedAchievements, @"SavedAchievements", nil];
    }
    
    [self storePlayerData:playerDict withKey:[self localPlayerID]];
    
    GKAchievement *achievement = [[GKAchievement alloc] initWithIdentifier:identifier];
    NSNumber *percentNumber = [NSNumber numberWithDouble:percentComplete];
    
    if (percentNumber && achievement) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([[self delegate] respondsToSelector:@selector(gameCenterManager:didSaveAchievement:)]) {
                [[self delegate] gameCenterManager:self didSaveAchievement:achievement];
            }
        });
    } else {
        NSError *error = [NSError errorWithDomain:[NSString stringWithFormat:@"Could not save achievement because necessary data is missing. GameCenter needs an Achievement ID and Percent Completed to save the achievement. You provided the following data:\nAchievement: %@\nPercent Completed:%@", achievement, percentNumber]
                                             code:GCMErrorAchievementDataMissing userInfo:nil];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([[self delegate] respondsToSelector:@selector(gameCenterManager:error:)])
                [[self delegate] gameCenterManager:self error:error];
        });
    }
}

//------------------------------------------------------------------------------------------------------------//
//------- Score, Achievement, and Challenge Retrieval --------------------------------------------------------//
//------------------------------------------------------------------------------------------------------------//
#pragma mark - Score, Achievement, and Challenge Retrieval

- (long long)highScoreForLeaderboard:(NSString *)identifier {
    
    NSMutableDictionary *playerDict = [self getPlayerDataOfClass:[NSMutableDictionary class] withKey:[self localPlayerID]];
    
    if (playerDict != nil) {
        NSNumber *savedHighScore = [playerDict objectForKey:identifier];
        if (savedHighScore != nil) {
            return [savedHighScore longLongValue];
        } else {
            return 0;
        }
    } else {
        return 0;
    }
}

- (NSDictionary *)highScoreForLeaderboards:(NSArray *)identifiers {
    NSMutableDictionary *playerDict = [self getPlayerDataOfClass:[NSMutableDictionary class] withKey:[self localPlayerID]];
    
    NSMutableDictionary *highScores = [[NSMutableDictionary alloc] initWithCapacity:identifiers.count];
    
    for (NSString *identifier in identifiers) {
        if (playerDict != nil) {
            NSNumber *savedHighScore = [playerDict objectForKey:identifier];
            
            if (savedHighScore != nil) {
                [highScores setObject:[NSNumber numberWithLongLong:[savedHighScore longLongValue]] forKey:identifier];
                continue;
            }
        }
        
        [highScores setObject:[NSNumber numberWithLongLong:0] forKey:identifier];
    }
    
    NSDictionary *highScoreDict = [NSDictionary dictionaryWithDictionary:highScores];
    
    return highScoreDict;
}

- (double)progressForAchievement:(NSString *)identifier {
    
    NSMutableDictionary *playerDict = [self getPlayerDataOfClass:[NSMutableDictionary class] withKey:[self localPlayerID]];
    
    if (playerDict != nil) {
        NSNumber *savedPercentComplete = [playerDict objectForKey:identifier];
        
        if (savedPercentComplete != nil) {
            return [savedPercentComplete doubleValue];
        }
    }
    return 0;
}

- (NSDictionary *)progressForAchievements:(NSArray *)identifiers {
    NSMutableDictionary *playerDict = [self getPlayerDataOfClass:[NSMutableDictionary class] withKey:[self localPlayerID]];
    
    NSMutableDictionary *percent = [[NSMutableDictionary alloc] initWithCapacity:identifiers.count];
    
    for (NSString *identifier in identifiers) {
        if (playerDict != nil) {
            NSNumber *savedPercentComplete = [playerDict objectForKey:identifier];
            
            if (savedPercentComplete != nil) {
                [percent setObject:[NSNumber numberWithDouble:[savedPercentComplete doubleValue]] forKey:identifier];
                continue;
            }
        }
        
        [percent setObject:[NSNumber numberWithDouble:0] forKey:identifier];
    }
    
    NSDictionary *percentDict = [NSDictionary dictionaryWithDictionary:percent];
    
    return percentDict;
}

- (void)getChallengesWithCompletion:(void (^)(NSArray *challenges, NSError *error))handler {
    if ([self checkGameCenterAvailability] == YES) {
        BOOL isGameCenterChallengeAPIAvailable = (NSClassFromString(@"GKChallenge")) != nil;
        
        if (isGameCenterChallengeAPIAvailable == YES) {
            [GKChallenge loadReceivedChallengesWithCompletionHandler:^(NSArray *challenges, NSError *error) {
                if (error == nil) {
                    handler(challenges, nil);
                } else {
                    handler(nil, error);
                }
            }];
        } else {
#if TARGET_OS_IPHONE
            NSError *error = [NSError errorWithDomain:[NSString stringWithFormat:@"GKChallenge Class is not available. GKChallenge is only available on iOS 6.0 and higher. Current iOS version: %@", [[UIDevice currentDevice] systemVersion]] code:GCMErrorFeatureNotAvailable userInfo:nil];
#else
            NSError *error = [NSError errorWithDomain:[NSString stringWithFormat:@"GKChallenge Class is not available. GKChallenge is only available on OS X 10.8.2 and higher."] code:GCMErrorFeatureNotAvailable userInfo:nil];
#endif
            if ([[self delegate] respondsToSelector:@selector(gameCenterManager:error:)])
                [[self delegate] gameCenterManager:self error:error];
        }
    } else {
        NSError *error = [NSError errorWithDomain:[NSString stringWithFormat:@"GameCenter Unavailable"] code:GCMErrorNotAvailable userInfo:nil];
        if ([[self delegate] respondsToSelector:@selector(gameCenterManager:error:)])
            [[self delegate] gameCenterManager:self error:error];
    }
}

//------------------------------------------------------------------------------------------------------------//
//------- Presenting GameKit Controllers ---------------------------------------------------------------------//
//------------------------------------------------------------------------------------------------------------//
#pragma mark - Presenting GameKit Controllers

#if TARGET_OS_OSX
- (void)presentAchievementsOnViewController:(NSViewController *)viewController
#else
- (void)presentAchievementsOnViewController:(UIViewController *)viewController
#endif
{
    GKGameCenterViewController *achievementsViewController = [[GKGameCenterViewController alloc] init];
    #if TARGET_OS_IOS || (TARGET_OS_IPHONE && !TARGET_OS_TV)
    achievementsViewController.viewState = GKGameCenterViewControllerStateAchievements;
    #endif
    achievementsViewController.gameCenterDelegate = self;
    
#if TARGET_OS_OSX
    [viewController presentViewControllerAsSheet:achievementsViewController];
#else
    [viewController presentViewController:achievementsViewController animated:YES completion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([[self delegate] respondsToSelector:@selector(gameCenterManager:gameCenterViewControllerPresented:)])
                [[self delegate] gameCenterManager:self gameCenterViewControllerPresented:YES];
        });
    }];
#endif
}

#if TARGET_OS_OSX
- (void)presentLeaderboardsOnViewController:(NSViewController *)viewController withLeaderboard:(NSString *)leaderboard
#else
- (void)presentLeaderboardsOnViewController:(UIViewController *)viewController withLeaderboard:(NSString *)leaderboard
#endif
{
    GKGameCenterViewController *leaderboardViewController = [[GKGameCenterViewController alloc] init];
    #if TARGET_OS_IOS || (TARGET_OS_IPHONE && !TARGET_OS_TV)
    leaderboardViewController.viewState = GKGameCenterViewControllerStateLeaderboards;
    /*
     Passing nil to leaderboardViewController.leaderboardIdentifier works fine,
     but to make sure future updates will not break, we'll check it first
     */
    if (leaderboard != nil) {
        leaderboardViewController.leaderboardIdentifier = leaderboard;
    }
    #elif TARGET_OS_TV
         #warning For tvOS you must set leaderboard ID's in the Assets catalogue - Click on this warning for more info.
        /**
         To get the Leaderboards to show up:
         1. Achievements and Leaderboards are merged into a single GameCenter view, with the Leaderboards shown above the achievements.
         2. For tvOS adding the Leaderboards to the GameViewController is all about the Image Assets.
         3. You must add a "+ -> GameCenter -> New Apple TV Leaderboard (or Set)." to your Image Asset.
         4. You must set the "Identifier" for this Leaderboard asset to exactly what your identifier is for each of your leaderboards. Example:
         grp.GameCenterManager.PlayerScores
         5. You must have the image sizes 659 × 371 for the Leaderboard Images.*/
    #endif
    leaderboardViewController.gameCenterDelegate = self;
    
#if TARGET_OS_OSX
    [viewController presentViewControllerAsSheet:leaderboardViewController];
#else
    [viewController presentViewController:leaderboardViewController animated:YES completion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([[self delegate] respondsToSelector:@selector(gameCenterManager:gameCenterViewControllerPresented:)])
                [[self delegate] gameCenterManager:self gameCenterViewControllerPresented:YES];
        });
    }];
#endif
}

#if TARGET_OS_OSX
- (void)presentChallengesOnViewController:(NSViewController *)viewController
#else
- (void)presentChallengesOnViewController:(UIViewController *)viewController
#endif
{
    GKGameCenterViewController *challengeViewController = [[GKGameCenterViewController alloc] init];
    #if TARGET_OS_IOS || (TARGET_OS_IPHONE && !TARGET_OS_TV)
    challengeViewController.viewState = GKGameCenterViewControllerStateChallenges;
    #endif
    challengeViewController.gameCenterDelegate = self;
    
#if TARGET_OS_OSX
    [viewController presentViewControllerAsSheet:challengeViewController];
#else
    [viewController presentViewController:challengeViewController animated:YES completion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([[self delegate] respondsToSelector:@selector(gameCenterManager:gameCenterViewControllerPresented:)])
                [[self delegate] gameCenterManager:self gameCenterViewControllerPresented:YES];
        });
    }];
#endif
}

- (void)gameCenterViewControllerDidFinish:(GKGameCenterViewController *)gameCenterViewController {
#if TARGET_OS_IPHONE
    [gameCenterViewController dismissViewControllerAnimated:YES completion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([[self delegate] respondsToSelector:@selector(gameCenterManager:gameCenterViewControllerDidFinish:)])
                [[self delegate] gameCenterManager:self gameCenterViewControllerDidFinish:YES];
        });
    }];
#else
    [gameCenterViewController dismissViewController:gameCenterViewController];
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([[self delegate] respondsToSelector:@selector(gameCenterManager:gameCenterViewControllerDidFinish:)])
            [[self delegate] gameCenterManager:self gameCenterViewControllerDidFinish:YES];
    });
#endif
}

//------------------------------------------------------------------------------------------------------------//
//------- Resetting Data -------------------------------------------------------------------------------------//
//------------------------------------------------------------------------------------------------------------//
#pragma mark - Resetting Data

- (void)resetAchievementsWithCompletion:(void (^)(NSError *))handler {
    if ([self isGameCenterAvailable]) {
        [GKAchievement loadAchievementsWithCompletionHandler:^(NSArray *achievements, NSError *error) {
            if (error == nil) {
                NSMutableDictionary *playerDict = [self getPlayerDataOfClass:[NSMutableDictionary class] withKey:[self localPlayerID]];
                
                if (playerDict == nil) {
                    playerDict = [NSMutableDictionary dictionary];
                }
                
                for (GKAchievement *achievement in achievements) {
                    [playerDict removeObjectForKey:achievement.identifier];
                }

                [self storePlayerData:playerDict withKey:[self localPlayerID]];
                
                [GKAchievement resetAchievementsWithCompletionHandler:^(NSError *error) {
                    if (error == nil) {
                        [USERDEFAULTS setBool:NO forKey:[@"achievementsSynced" stringByAppendingString:[self localPlayerID]]];
                        [USERDEFAULTS synchronize];
                        
                        [self syncGameCenter];
                        
                        dispatch_async(dispatch_get_main_queue(), ^{
                            handler(nil);
                        });
                    } else {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            handler(error);
                        });
                    }
                }];
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    handler(error);
                });
            }
        }];
    }
}

//------------------------------------------------------------------------------------------------------------//
//------- Player Data ----------------------------------------------------------------------------------------//
//------------------------------------------------------------------------------------------------------------//
#pragma mark - Player Data

- (NSString *)localPlayerID {
    if ([self isGameCenterAvailable]) {
        if ([GKLocalPlayer localPlayer].authenticated) {
            return [GKLocalPlayer localPlayer].gamePlayerID;
        }
    }
    return @"unknownPlayer";
}

- (NSString *)localPlayerDisplayName {
    if ([self isGameCenterAvailable] && [GKLocalPlayer localPlayer].authenticated) {
        if ([[GKLocalPlayer localPlayer] respondsToSelector:@selector(displayName)]) {
            return [GKLocalPlayer localPlayer].displayName;
        } else {
            return [GKLocalPlayer localPlayer].alias;
        }
    }
    
    return @"unknownPlayer";
}

- (GKLocalPlayer *)localPlayerData {
    if ([self isGameCenterAvailable] && [GKLocalPlayer localPlayer].authenticated) {
        return [GKLocalPlayer localPlayer];
    } else {
        return nil;
    }
}

#if TARGET_OS_IPHONE
- (void)localPlayerPhoto:(void (^)(UIImage *playerPhoto))handler {
    if ([self isGameCenterAvailable]) {
        [[self localPlayerData] loadPhotoForSize:GKPhotoSizeNormal withCompletionHandler:^(UIImage *photo, NSError *error) {
            handler(photo);
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([[self delegate] respondsToSelector:@selector(gameCenterManager:error:)])
                        [[self delegate] gameCenterManager:self error:error];
                });
            }
        }];
    } else {
        NSError *error = [NSError errorWithDomain:[NSString stringWithFormat:@"GameCenter Unavailable"] code:GCMErrorNotAvailable userInfo:nil];
        if ([[self delegate] respondsToSelector:@selector(gameCenterManager:error:)])
            [[self delegate] gameCenterManager:self error:error];
    }
}
#else
- (void)localPlayerPhoto:(void (^)(NSImage *playerPhoto))handler {
    if ([self isGameCenterAvailable]) {
        [[self localPlayerData] loadPhotoForSize:GKPhotoSizeNormal withCompletionHandler:^(NSImage *photo, NSError *error) {
            handler(photo);
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([[self delegate] respondsToSelector:@selector(gameCenterManager:error:)])
                        [[self delegate] gameCenterManager:self error:error];
                });
            }
        }];
    } else {
        NSError *error = [NSError errorWithDomain:[NSString stringWithFormat:@"GameCenter Unavailable"] code:GCMErrorNotAvailable userInfo:nil];
        if ([[self delegate] respondsToSelector:@selector(gameCenterManager:error:)])
            [[self delegate] gameCenterManager:self error:error];
    }
}
#endif

@end
