#!/usr/bin/env python3
"""Generate JustDiary.xcodeproj for the iOS migration of the HarmonyOS JustDiary app."""
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.join(ROOT, "JustDiary.xcodeproj")

ICON_REF = "97EDEE5130319B09000E17D3"
ICON_BUILD = "97EDEE5230319B09000E17D3"
APP_SYNC = "A10000000000000000000001"
APP_TARGET = "B10000000000000000000001"
APP_PRODUCT = "C10000000000000000000001"
APP_EXC = "A10000000000000000000003"
UITEST_SYNC = "A10000000000000000000005"
UITEST_TARGET = "B10000000000000000000003"
UITEST_PRODUCT = "C10000000000000000000003"
PROJECT_OBJ = "E10000000000000000000001"
MAIN_GROUP = "F10000000000000000000001"
PRODUCTS_GROUP = "F10000000000000000000002"
APP_SOURCES = "F10000000000000000000003"
APP_FRAMEWORKS = "F10000000000000000000004"
APP_RESOURCES = "F10000000000000000000005"
UITEST_SOURCES = "F1000000000000000000000A"
UITEST_FRAMEWORKS = "F1000000000000000000000B"
UITEST_RESOURCES = "F1000000000000000000000C"
PROJ_CFG_DEBUG = "A20000000000000000000001"
PROJ_CFG_RELEASE = "A20000000000000000000002"
APP_CFG_DEBUG = "A20000000000000000000003"
APP_CFG_RELEASE = "A20000000000000000000004"
PROJ_CFGLIST = "A20000000000000000000007"
APP_CFGLIST = "A20000000000000000000008"
UITEST_CFG_DEBUG = "A2000000000000000000000B"
UITEST_CFG_RELEASE = "A2000000000000000000000C"
UITEST_CFGLIST = "A2000000000000000000000D"
UITEST_DEP = "A2000000000000000000000E"
UITEST_PROXY = "A3000000000000000000000B"

def pbx(build_settings, name, base):
    lines = []
    for k in sorted(build_settings):
        v = build_settings[k]
        if isinstance(v, list):
            lines.append(f"\t\t\t\t{k} = (\n")
            for item in v:
                lines.append(f'\t\t\t\t\t"{item}",\n')
            lines.append("\t\t\t\t);")
        else:
            lines.append(f'\t\t\t\t{k} = {v};')
    return "\n".join(lines)

# Settings shared by both project-level configurations. Mirrors the Xcode 27
# "Base_ProjectSettings" template so the project builds with the same analyzer
# and warning baseline as a freshly created Xcode 27 app.
project_common_settings = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
    # Must stay quoted: '+' is not legal in an unquoted OpenStep plist string.
    "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
    "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
    "CLANG_WARN_BOOL_CONVERSION": "YES",
    "CLANG_WARN_COMMA": "YES",
    "CLANG_WARN_CONSTANT_CONVERSION": "YES",
    "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
    "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_EMPTY_BODY": "YES",
    "CLANG_WARN_ENUM_CONVERSION": "YES",
    "CLANG_WARN_INFINITE_RECURSION": "YES",
    "CLANG_WARN_INT_CONVERSION": "YES",
    "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
    "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
    "CLANG_WARN_STRICT_PROTOTYPES": "YES",
    "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
    "CLANG_WARN_UNREACHABLE_CODE": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    # The project ships a String Catalog rather than .strings/.stringsdict.
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "iphoneos",
}

# Swift 6.4 / Xcode 27 concurrency defaults used by new app targets. MainActor
# default isolation makes every unannotated declaration main-actor isolated, so
# the few genuinely-off-main routines must be marked `nonisolated` explicitly.
swift_concurrency_settings = {
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
}

project_settings = {
    "Debug": {
        **project_common_settings,
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_DYNAMIC_NO_PIC": "NO",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
        "IPHONEOS_DEPLOYMENT_TARGET": "27.0",
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["DEBUG", "$(inherited)"],
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    },
    "Release": {
        **project_common_settings,
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO",
        "IPHONEOS_DEPLOYMENT_TARGET": "27.0",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": "-O",
        "VALIDATE_PRODUCT": "YES",
    },
}

# iPhone + iPad. Device family 2 is what makes the app eligible to ship as a
# "Designed for iPad" app that runs natively on Apple-silicon Macs.
_device_family = '"1,2"'
_oriented_phone = ('"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft '
                  'UIInterfaceOrientationLandscapeRight"')
_oriented_pad = ('"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown '
                'UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"')

app_common_settings = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": '"JustDiary"',
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "JustDiary/JustDiary.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "JustDiary/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "\"一页时光\"",
    "INFOPLIST_KEY_LSApplicationCategoryType": "\"public.app-category.lifestyle\"",
    # Xcode 27 migrated this out of Info.plist into a build setting. Without it,
    # requesting location authorization terminates the app on a real device.
    "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription": "\"用于在写日记时自动记录所在位置\"",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": _oriented_pad,
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": _oriented_phone,
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.cov.justdiary",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SUPPORTED_PLATFORMS": "\"iphoneos iphonesimulator\"",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": _device_family,
    **swift_concurrency_settings,
}

app_settings = {"Debug": app_common_settings, "Release": app_common_settings}

uitest_common_settings = {
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.cov.justdiary.uitests",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SUPPORTED_PLATFORMS": "\"iphoneos iphonesimulator\"",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": _device_family,
    "TEST_TARGET_NAME": "JustDiary",
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
}

uitest_settings = {"Debug": uitest_common_settings, "Release": uitest_common_settings}

def settings_block(cfg_id, name, settings):
    body = pbx(settings, name, "XCBuildConfiguration")
    return (
        f"\t\t{cfg_id} /* {name} */ = {{\n"
        f"\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n{body}\n\t\t\t}};\n"
        f"\t\t\tname = {name};\n"
        f"\t\t}};"
    )

content = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
		{ICON_BUILD} /* JustDiary.icon in Resources */ = {{isa = PBXBuildFile; fileRef = {ICON_REF} /* JustDiary.icon */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		{ICON_REF} /* JustDiary.icon */ = {{isa = PBXFileReference; lastKnownFileType = folder.iconcomposer.icon; path = "JustDiary.icon"; sourceTree = "<group>"; }};
		{APP_PRODUCT} /* JustDiary.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = JustDiary.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{UITEST_PRODUCT} /* JustDiaryUITests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = JustDiaryUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
		{APP_EXC} /* Exceptions for "JustDiary" folder in "JustDiary" target */ = {{
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Info.plist,
			);
			target = {APP_TARGET} /* JustDiary */;
		}};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{APP_SYNC} /* JustDiary */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				{APP_EXC} /* Exceptions for "JustDiary" folder in "JustDiary" target */,
			);
			path = JustDiary;
			sourceTree = "<group>";
		}};
		{UITEST_SYNC} /* JustDiaryUITests */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = JustDiaryUITests;
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{APP_FRAMEWORKS} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{UITEST_FRAMEWORKS} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{MAIN_GROUP} = {{
			isa = PBXGroup;
			children = (
				{APP_SYNC} /* JustDiary */,
				{UITEST_SYNC} /* JustDiaryUITests */,
				{PRODUCTS_GROUP} /* Products */,
				{ICON_REF} /* JustDiary.icon */,
			);
			sourceTree = "<group>";
		}};
		{PRODUCTS_GROUP} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{APP_PRODUCT} /* JustDiary.app */,
				{UITEST_PRODUCT} /* JustDiaryUITests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{APP_TARGET} /* JustDiary */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {APP_CFGLIST} /* Build configuration list for PBXNativeTarget "JustDiary" */;
			buildPhases = (
				{APP_SOURCES} /* Sources */,
				{APP_FRAMEWORKS} /* Frameworks */,
				{APP_RESOURCES} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{APP_SYNC} /* JustDiary */,
			);
			name = JustDiary;
			packageProductDependencies = (
			);
			productName = JustDiary;
			productReference = {APP_PRODUCT} /* JustDiary.app */;
			productType = "com.apple.product-type.application";
		}};
		{UITEST_TARGET} /* JustDiaryUITests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {UITEST_CFGLIST} /* Build configuration list for PBXNativeTarget "JustDiaryUITests" */;
			buildPhases = (
				{UITEST_SOURCES} /* Sources */,
				{UITEST_FRAMEWORKS} /* Frameworks */,
				{UITEST_RESOURCES} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				{UITEST_DEP} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{UITEST_SYNC} /* JustDiaryUITests */,
			);
			name = JustDiaryUITests;
			packageProductDependencies = (
			);
			productName = JustDiaryUITests;
			productReference = {UITEST_PRODUCT} /* JustDiaryUITests.xctest */;
			productType = "com.apple.product-type.bundle.ui-testing";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{PROJECT_OBJ} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2700;
				LastUpgradeCheck = 2700;
				TargetAttributes = {{
					{APP_TARGET} = {{
						CreatedOnToolsVersion = 27.0;
					}};
					{UITEST_TARGET} = {{
						CreatedOnToolsVersion = 27.0;
						TestTargetID = {APP_TARGET};
					}};
				}};
			}};
			buildConfigurationList = {PROJ_CFGLIST} /* Build configuration list for PBXProject "JustDiary" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				"zh-Hans",
				Base,
			);
			mainGroup = {MAIN_GROUP} /* main */;
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			productRefGroup = {PRODUCTS_GROUP} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{APP_TARGET} /* JustDiary */,
				{UITEST_TARGET} /* JustDiaryUITests */,
			);
			testTargets = (
				{UITEST_TARGET} /* JustDiaryUITests */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{APP_RESOURCES} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{ICON_BUILD} /* JustDiary.icon in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{UITEST_RESOURCES} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{APP_SOURCES} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{UITEST_SOURCES} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{UITEST_DEP} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {APP_TARGET} /* JustDiary */;
			targetProxy = {UITEST_PROXY} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin PBXContainerItemProxy section */
		{UITEST_PROXY} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {PROJECT_OBJ} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {APP_TARGET};
			remoteInfo = JustDiary;
		}};
/* End PBXContainerItemProxy section */

/* Begin XCBuildConfiguration section */
{settings_block(PROJ_CFG_DEBUG, "Debug", project_settings["Debug"])}

{settings_block(PROJ_CFG_RELEASE, "Release", project_settings["Release"])}

{settings_block(APP_CFG_DEBUG, "Debug", app_settings["Debug"])}

{settings_block(APP_CFG_RELEASE, "Release", app_settings["Release"])}

{settings_block(UITEST_CFG_DEBUG, "Debug", uitest_settings["Debug"])}

{settings_block(UITEST_CFG_RELEASE, "Release", uitest_settings["Release"])}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{PROJ_CFGLIST} /* Build configuration list for PBXProject "JustDiary" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{PROJ_CFG_DEBUG} /* Debug */,
				{PROJ_CFG_RELEASE} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{APP_CFGLIST} /* Build configuration list for PBXNativeTarget "JustDiary" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{APP_CFG_DEBUG} /* Debug */,
				{APP_CFG_RELEASE} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{UITEST_CFGLIST} /* Build configuration list for PBXNativeTarget "JustDiaryUITests" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{UITEST_CFG_DEBUG} /* Debug */,
				{UITEST_CFG_RELEASE} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {PROJECT_OBJ} /* Project object */;
}}
"""

os.makedirs(PROJ, exist_ok=True)
with open(os.path.join(PROJ, "project.pbxproj"), "w") as f:
    f.write(content)
print("project.pbxproj written")
