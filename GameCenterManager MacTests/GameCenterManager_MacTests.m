//
//  GameCenterManager_MacTests.m
//  GameCenterManager MacTests
//
//  Created by Peter Easdown on 1/1/21.
//  Copyright © 2021 NABZ Software. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "GameCenterManager.h"

@interface GameCenterManager_MacTests : XCTestCase

@end

@implementation GameCenterManager_MacTests

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
    XCTAssertFalse([GameCenterManager sharedManager].isInternetAvailable, @"Don't try to run these tests when GameCenter is available.");
    
    [USERDEFAULTS removeObjectForKey:[[GameCenterManager sharedManager] localPlayerID]];
    [USERDEFAULTS removeObjectForKey:[[GameCenterManager sharedManager] savedScoresKey]];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testSaveAndReportScoreHighToLow {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
    [[GameCenterManager sharedManager] saveAndReportScore:51 leaderboard:@"testLeaderboard" sortOrder:GameCenterSortOrderHighToLow];
    
    XCTAssertEqual(51, [[GameCenterManager sharedManager] highScoreForLeaderboard:@"testLeaderboard"]);
    XCTAssertNotEqual(51, [[GameCenterManager sharedManager] highScoreForLeaderboard:@"testLeaderboard2"]);
    
    [[GameCenterManager sharedManager] saveAndReportScore:55 leaderboard:@"testLeaderboard" sortOrder:GameCenterSortOrderHighToLow];
    
    XCTAssertEqual(55, [[GameCenterManager sharedManager] highScoreForLeaderboard:@"testLeaderboard"]);
    
    [[GameCenterManager sharedManager] saveAndReportScore:45 leaderboard:@"testLeaderboard" sortOrder:GameCenterSortOrderHighToLow];
    
    XCTAssertEqual(55, [[GameCenterManager sharedManager] highScoreForLeaderboard:@"testLeaderboard"]);
}

- (void)testSaveAndReportScoreLowToHigh {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
    [[GameCenterManager sharedManager] saveAndReportScore:45 leaderboard:@"testLeaderboardL2H" sortOrder:GameCenterSortOrderLowToHigh];
    
    XCTAssertEqual(45, [[GameCenterManager sharedManager] highScoreForLeaderboard:@"testLeaderboardL2H"]);
    XCTAssertNotEqual(34, [[GameCenterManager sharedManager] highScoreForLeaderboard:@"testLeaderboard2"]);
    
    [[GameCenterManager sharedManager] saveAndReportScore:41 leaderboard:@"testLeaderboardL2H" sortOrder:GameCenterSortOrderLowToHigh];
    
    XCTAssertEqual(41, [[GameCenterManager sharedManager] highScoreForLeaderboard:@"testLeaderboardL2H"]);
    
    [[GameCenterManager sharedManager] saveAndReportScore:54 leaderboard:@"testLeaderboardL2H" sortOrder:GameCenterSortOrderLowToHigh];
    
    XCTAssertEqual(41, [[GameCenterManager sharedManager] highScoreForLeaderboard:@"testLeaderboardL2H"]);
}

- (void) testSaveAndReportAchievement {
    [[GameCenterManager sharedManager] saveAndReportScore:45 leaderboard:@"testLeaderboardL2H" sortOrder:GameCenterSortOrderLowToHigh];

    [[GameCenterManager sharedManager] saveAndReportAchievement:@"ach1" percentComplete:40 shouldDisplayNotification:NO];
    
    XCTAssertEqual(40, [[GameCenterManager sharedManager] progressForAchievement:@"ach1"]);

    [[GameCenterManager sharedManager] saveAndReportAchievement:@"ach2" percentComplete:70 shouldDisplayNotification:NO];
    
    XCTAssertEqual(40, [[GameCenterManager sharedManager] progressForAchievement:@"ach1"]);
    XCTAssertEqual(70, [[GameCenterManager sharedManager] progressForAchievement:@"ach2"]);

    [[GameCenterManager sharedManager] saveAndReportAchievement:@"ach1" percentComplete:55 shouldDisplayNotification:NO];
    
    XCTAssertEqual(55, [[GameCenterManager sharedManager] progressForAchievement:@"ach1"]);
    XCTAssertEqual(70, [[GameCenterManager sharedManager] progressForAchievement:@"ach2"]);
        
    XCTAssertEqual(45, [[GameCenterManager sharedManager] highScoreForLeaderboard:@"testLeaderboardL2H"]);
    XCTAssertEqual(55, [[GameCenterManager sharedManager] progressForAchievement:@"ach1"]);
    XCTAssertEqual(70, [[GameCenterManager sharedManager] progressForAchievement:@"ach2"]);
}

@end
