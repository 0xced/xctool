//
// Copyright 2013 Facebook
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <SenTestingKit/SenTestingKit.h>

#import "Action.h"
#import "BuildTestsAction.h"
#import "FakeTask.h"
#import "FakeTaskManager.h"
#import "LaunchHandlers.h"
#import "Options.h"
#import "Options+Testing.h"
#import "SchemeGenerator.h"
#import "Swizzler.h"
#import "TaskUtil.h"
#import "TestUtil.h"
#import "XCTool.h"
#import "XCToolUtil.h"
#import "xcodeSubjectInfo.h"

static NSString *kTestProjectTestProjectLibraryTargetID         = @"2828291F16B11F0F00426B92";
static NSString *kTestProjectTestProjectLibraryTestTargetID     = @"2828293016B11F0F00426B92";
static NSString *kTestWorkspaceTestProjectLibraryTargetID       = @"28A33CCF16CF03EA00C5EE2A";
static NSString *kTestWorkspaceTestProjectLibraryTestsTargetID  = @"28A33CE016CF03EA00C5EE2A";
static NSString *kTestWorkspaceTestProjectLibraryTests2TargetID = @"28ADB42416E40E23006301ED";
static NSString *kTestWorkspaceTestProjectOtherLibTargetID      = @"28ADB45F16E42E9A006301ED";

@interface BuildTestsActionTests : SenTestCase
@end

@implementation BuildTestsActionTests

- (void)setUp
{
  [super setUp];
}

- (void)testOnlyListIsCollected
{
  Options *options = [[Options optionsFrom:@[
                       @"-project", TEST_DATA @"TestProject-Library/TestProject-Library.xcodeproj",
                       @"-scheme", @"TestProject-Library",
                       @"-sdk", @"iphonesimulator6.1",
                       @"build-tests", @"-only", @"TestProject-LibraryTests",
                       ]] assertOptionsValidateWithBuildSettingsFromFile:
                      TEST_DATA @"TestProject-Library-TestProject-Library-showBuildSettings.txt"
                      ];
  BuildTestsAction *action = options.actions[0];
  assertThat((action.onlyList), equalTo(@[@"TestProject-LibraryTests"]));
}


- (void)testSkipDependenciesIsCollected
{
  Options *options = [[Options optionsFrom:@[
                       @"-project", TEST_DATA @"TestProject-Library/TestProject-Library.xcodeproj",
                       @"-scheme", @"TestProject-Library",
                       @"-sdk", @"iphonesimulator6.1",
                       @"build-tests", @"-only", @"TestProject-LibraryTests",
                       @"-skip-deps"
                       ]] assertOptionsValidateWithBuildSettingsFromFile:
                      TEST_DATA @"TestProject-Library-TestProject-Library-showBuildSettings.txt"
                      ];
  BuildTestsAction *action = options.actions[0];
  assertThatBool(action.skipDependencies, equalToBool(YES));
}

- (void)testOnlyListRequiresValidTarget
{
  [[Options optionsFrom:@[
    @"-project", TEST_DATA @"TestProject-Library/TestProject-Library.xcodeproj",
    @"-scheme", @"TestProject-Library",
    @"-sdk", @"iphonesimulator6.1",
    @"build-tests", @"-only", @"BOGUS_TARGET",
    ]]
   assertOptionsFailToValidateWithError:
   @"build-tests: 'BOGUS_TARGET' is not a testing target in this scheme."
   withBuildSettingsFromFile:
   TEST_DATA @"TestProject-Library-TestProject-Library-showBuildSettings.txt"
   ];
}

- (void)testBuildTestsAction
{
  [[FakeTaskManager sharedManager] runBlockWithFakeTasks:^{
    [[FakeTaskManager sharedManager] addLaunchHandlerBlocks:@[
     // Make sure -showBuildSettings returns some data
     [LaunchHandlers handlerForShowBuildSettingsWithProject:TEST_DATA @"TestProject-Library/TestProject-Library.xcodeproj"
                                                     scheme:@"TestProject-Library"
                                               settingsPath:TEST_DATA @"TestProject-Library-showBuildSettings.txt"],
     ]];

    NSString *mockWorkspacePath = @"/tmp/nowhere/build_tests_tmp.xcworkspace";
    id mockSchemeGenerator = mock([SchemeGenerator class]);
    [given([mockSchemeGenerator writeWorkspaceNamed:@"build_tests_tmp"])
     willReturn:mockWorkspacePath];

    XCTool *tool = [[[XCTool alloc] init] autorelease];

    tool.arguments = @[
                       @"-project", TEST_DATA @"TestProject-Library/TestProject-Library.xcodeproj",
                       @"-scheme", @"TestProject-Library",
                       @"-configuration", @"Debug",
                       @"-sdk", @"iphonesimulator6.0",
                       @"build-tests"
                       ];

    [Swizzler whileSwizzlingSelector:@selector(schemeGenerator)
                            forClass:[SchemeGenerator class]
                           withBlock:^(Class c, SEL sel){ return mockSchemeGenerator; }
                            runBlock:^{ [TestUtil runWithFakeStreams:tool]; }];

    NSArray *launchedTasks = [[FakeTaskManager sharedManager] launchedTasks];
    assertThatInteger([launchedTasks count], equalToInteger(1));
    assertThat([launchedTasks[0] arguments],
               equalTo(@[
                       @"-configuration", @"Debug",
                       @"-sdk", @"iphonesimulator6.0",
                       @"-workspace", mockWorkspacePath,
                       @"-scheme", @"build_tests_tmp",
                       @"OBJROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestProject-Library-amxcwsnetnrvhrdeikqmcczcgmwn/Build/Intermediates",
                       @"SYMROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestProject-Library-amxcwsnetnrvhrdeikqmcczcgmwn/Build/Products",
                       @"SHARED_PRECOMPS_DIR=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestProject-Library-amxcwsnetnrvhrdeikqmcczcgmwn/Build/Intermediates/PrecompiledHeaders",
                       @"build",
                       ]));
    assertThatInt(tool.exitStatus, equalToInt(0));

    NSString *projectPath = TEST_DATA @"TestProject-Library/TestProject-Library.xcodeproj";
    [verify(mockSchemeGenerator) addBuildableWithID:kTestProjectTestProjectLibraryTargetID
                                          inProject:projectPath];
    [verify(mockSchemeGenerator) addBuildableWithID:kTestProjectTestProjectLibraryTestTargetID
                                          inProject:projectPath];
    [verify(mockSchemeGenerator) writeWorkspaceNamed:@"build_tests_tmp"];
  }];
}

- (void)testBuildTestsActionWillBuildEverythingMarkedAsBuildForTest
{
  [[FakeTaskManager sharedManager] runBlockWithFakeTasks:^{
    [[FakeTaskManager sharedManager] addLaunchHandlerBlocks:@[
     // Make sure -showBuildSettings returns some data
     [LaunchHandlers handlerForShowBuildSettingsWithWorkspace:TEST_DATA @"TestWorkspace-Library/TestWorkspace-Library.xcworkspace"
                                                       scheme:@"TestProject-Library"
                                                 settingsPath:TEST_DATA @"TestWorkspace-Library-TestProject-Library-showBuildSettings.txt"],
     ]];

    NSString *mockWorkspacePath = @"/tmp/nowhere/build_tests_tmp.xcworkspace";
    id mockSchemeGenerator = mock([SchemeGenerator class]);
    [given([mockSchemeGenerator writeWorkspaceNamed:@"build_tests_tmp"])
     willReturn:mockWorkspacePath];

    XCTool *tool = [[[XCTool alloc] init] autorelease];

    tool.arguments = @[
                       @"-workspace", TEST_DATA @"TestWorkspace-Library/TestWorkspace-Library.xcworkspace",
                       @"-scheme", @"TestProject-Library",
                       @"-configuration", @"Debug",
                       @"-sdk", @"iphonesimulator6.0",
                       @"build-tests"
                       ];

    [Swizzler whileSwizzlingSelector:@selector(schemeGenerator)
                            forClass:[SchemeGenerator class]
                           withBlock:^(Class c, SEL sel){ return mockSchemeGenerator; }
                            runBlock:^{ [TestUtil runWithFakeStreams:tool]; }];

    NSArray *launchedTasks = [[FakeTaskManager sharedManager] launchedTasks];
    assertThatInteger([launchedTasks count], equalToInteger(1));
    assertThat([launchedTasks[0] arguments],
               equalTo(@[
                       @"-configuration", @"Debug",
                       @"-sdk", @"iphonesimulator6.0",
                       @"-workspace", mockWorkspacePath,
                       @"-scheme", @"build_tests_tmp",
                       @"OBJROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Intermediates",
                       @"SYMROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Products",
                       @"SHARED_PRECOMPS_DIR=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Intermediates/PrecompiledHeaders",
                       @"build",
                       ]));
    assertThatInt(tool.exitStatus, equalToInt(0));

    NSString *projectPath = TEST_DATA @"TestWorkspace-Library/TestProject-Library/TestProject-Library.xcodeproj";
    [verify(mockSchemeGenerator) addBuildableWithID:kTestWorkspaceTestProjectLibraryTargetID
                                          inProject:projectPath];
    [verify(mockSchemeGenerator) addBuildableWithID:kTestWorkspaceTestProjectOtherLibTargetID
                                          inProject:projectPath];
    [verify(mockSchemeGenerator) addBuildableWithID:kTestWorkspaceTestProjectLibraryTestsTargetID
                                          inProject:projectPath];
    [verify(mockSchemeGenerator) addBuildableWithID:kTestWorkspaceTestProjectLibraryTests2TargetID
                                          inProject:projectPath];
    [verify(mockSchemeGenerator) writeWorkspaceNamed:@"build_tests_tmp"];
  }];
}

- (void)testBuildTestsCanBuildASingleTarget
{
  // In TestWorkspace-Library, we have a target TestProject-LibraryTest2 that depends on
  // TestProject-OtherLib, but it isn't marked as an explicit dependency.  The only way that
  // dependency gets built is that it's added to the scheme as build-for-test above
  // TestProject-LibraryTest2.  This a lame way to setup dependencies (they should be explicit),
  // but we're seeing this in the wild and should support it.
  [[FakeTaskManager sharedManager] runBlockWithFakeTasks:^{
    [[FakeTaskManager sharedManager] addLaunchHandlerBlocks:@[
     // Make sure -showBuildSettings returns some data
     [LaunchHandlers handlerForShowBuildSettingsWithWorkspace:TEST_DATA @"TestWorkspace-Library/TestWorkspace-Library.xcworkspace"
                                                       scheme:@"TestProject-Library"
                                                 settingsPath:TEST_DATA @"TestWorkspace-Library-TestProject-Library-showBuildSettings.txt"],
     ]];

    NSString *mockWorkspacePath = @"/tmp/nowhere/build_tests_tmp.xcworkspace";
    id mockSchemeGenerator = mock([SchemeGenerator class]);
    [given([mockSchemeGenerator writeWorkspaceNamed:@"build_tests_tmp"])
     willReturn:mockWorkspacePath];

    XCTool *tool = [[[XCTool alloc] init] autorelease];

    tool.arguments = @[
                       @"-workspace", TEST_DATA @"TestWorkspace-Library/TestWorkspace-Library.xcworkspace",
                       @"-scheme", @"TestProject-Library",
                       @"-configuration", @"Debug",
                       @"-sdk", @"iphonesimulator6.0",
                       @"build-tests", @"-only", @"TestProject-LibraryTests"
                       ];

    [Swizzler whileSwizzlingSelector:@selector(schemeGenerator)
                            forClass:[SchemeGenerator class]
                           withBlock:^(Class c, SEL sel){ return mockSchemeGenerator; }
                            runBlock:^{ [TestUtil runWithFakeStreams:tool]; }];

    NSArray *launchedTasks = [[FakeTaskManager sharedManager] launchedTasks];
    assertThatInteger([launchedTasks count], equalToInteger(1));
    assertThat([launchedTasks[0] arguments],
               equalTo(@[
                       @"-configuration", @"Debug",
                       @"-sdk", @"iphonesimulator6.0",
                       @"-workspace", mockWorkspacePath,
                       @"-scheme", @"build_tests_tmp",
                       @"OBJROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Intermediates",
                       @"SYMROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Products",
                       @"SHARED_PRECOMPS_DIR=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Intermediates/PrecompiledHeaders",
                       @"build",
                       ]));
    assertThatInt(tool.exitStatus, equalToInt(0));

    NSString *projectPath = TEST_DATA @"TestWorkspace-Library/TestProject-Library/TestProject-Library.xcodeproj";
    [verify(mockSchemeGenerator) addBuildableWithID:kTestWorkspaceTestProjectLibraryTargetID
                                          inProject:projectPath];
    [verify(mockSchemeGenerator) addBuildableWithID:kTestWorkspaceTestProjectOtherLibTargetID
                                          inProject:projectPath];
    [verify(mockSchemeGenerator) addBuildableWithID:kTestWorkspaceTestProjectLibraryTestsTargetID
                                          inProject:projectPath];
    [verifyCount(mockSchemeGenerator, times(3)) addBuildableWithID:(id)anything() inProject:(id)anything()];
    [verify(mockSchemeGenerator) writeWorkspaceNamed:@"build_tests_tmp"];
  }];
}


- (void)testSkipDependencies
{
  [[FakeTaskManager sharedManager] runBlockWithFakeTasks:^{
    [[FakeTaskManager sharedManager] addLaunchHandlerBlocks:@[
     // Make sure -showBuildSettings returns some data
     [LaunchHandlers handlerForShowBuildSettingsWithWorkspace:TEST_DATA @"TestWorkspace-Library/TestWorkspace-Library.xcworkspace"
                                                       scheme:@"TestProject-Library"
                                                 settingsPath:TEST_DATA @"TestWorkspace-Library-TestProject-Library-showBuildSettings.txt"],
     ]];

    NSString *mockWorkspacePath = @"/tmp/nowhere/build_tests_tmp.xcworkspace";
    id mockSchemeGenerator = mock([SchemeGenerator class]);
    [given([mockSchemeGenerator writeWorkspaceNamed:@"build_tests_tmp"])
     willReturn:mockWorkspacePath];

    XCTool *tool = [[[XCTool alloc] init] autorelease];

    tool.arguments = @[
                       @"-workspace", TEST_DATA @"TestWorkspace-Library/TestWorkspace-Library.xcworkspace",
                       @"-scheme", @"TestProject-Library",
                       @"-configuration", @"Debug",
                       @"-sdk", @"iphonesimulator6.0",
                       @"build-tests",
                       @"-only", @"TestProject-LibraryTests",
                       @"-skip-deps"
                       ];

    [Swizzler whileSwizzlingSelector:@selector(schemeGenerator)
                            forClass:[SchemeGenerator class]
                           withBlock:^(Class c, SEL sel){ return mockSchemeGenerator; }
                            runBlock:^{ [TestUtil runWithFakeStreams:tool]; }];

    NSArray *launchedTasks = [[FakeTaskManager sharedManager] launchedTasks];
    assertThatInteger([launchedTasks count], equalToInteger(1));
    assertThat([launchedTasks[0] arguments],
               equalTo(@[
                       @"-configuration", @"Debug",
                       @"-sdk", @"iphonesimulator6.0",
                       @"-workspace", mockWorkspacePath,
                       @"-scheme", @"build_tests_tmp",
                       @"OBJROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Intermediates",
                       @"SYMROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Products",
                       @"SHARED_PRECOMPS_DIR=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Intermediates/PrecompiledHeaders",
                       @"build",
                       ]));
    assertThatInt(tool.exitStatus, equalToInt(0));

    NSString *projectPath = TEST_DATA @"TestWorkspace-Library/TestProject-Library/TestProject-Library.xcodeproj";
    [verify(mockSchemeGenerator) addBuildableWithID:kTestWorkspaceTestProjectLibraryTestsTargetID
                                          inProject:projectPath];
    [verifyCount(mockSchemeGenerator, times(1)) addBuildableWithID:(id)anything() inProject:(id)anything()];
    [verify(mockSchemeGenerator) writeWorkspaceNamed:@"build_tests_tmp"];
  }];
}

@end
