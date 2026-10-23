#!/usr/bin/env python3
"""Generate a dependency-free, deterministic Xcode project. Run after adding Swift files."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parent.parent
project = root / 'LingoWisp.xcodeproj'
project.mkdir(exist_ok=True)
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
objects = []
def add(name, value):
    key = ident(name)
    objects.append(f'{key} = {{ {value} }};')
    return key
def refs(items): return '(' + ', '.join(items) + ',)'
sources = sorted((root / 'LingoWisp').rglob('*.swift'))
file_ids, build_ids = [], []
for source in sources:
    rel = str(source.relative_to(root))
    fid = add(rel, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{rel}"; sourceTree = SOURCE_ROOT;')
    file_ids.append(fid)
    build_ids.append(add('build:'+rel, f'isa = PBXBuildFile; fileRef = {fid};'))
icon = add('icon', 'isa = PBXFileReference; lastKnownFileType = image.icns; path = LingoWisp/Resources/AppIcon.icns; sourceTree = SOURCE_ROOT;')
icon_build = add('iconBuild', f'isa = PBXBuildFile; fileRef = {icon};')
file_ids.append(icon)
product = add('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = LingoWisp.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = add('products', f'isa = PBXGroup; children = {refs([product])}; name = Products; sourceTree = "<group>";')
group = add('mainGroup', f'isa = PBXGroup; children = {refs(file_ids + [products])}; sourceTree = "<group>";')
phase = add('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(build_ids)}; runOnlyForDeploymentPostprocessing = 0;')
frameworks = add('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
resources = add('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {refs([icon_build])}; runOnlyForDeploymentPostprocessing = 0;')
proj_configs, target_configs = [], []
# Preserve the original bundle ID so preferences and login-item identity survive the rename.
for mode in ['Debug', 'Release']:
    opt = '-Onone' if mode == 'Debug' else '-O'
    proj_configs.append(add('project'+mode, f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ MACOSX_DEPLOYMENT_TARGET = 15.0; SDKROOT = macosx; CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0; SWIFT_STRICT_CONCURRENCY = complete; SWIFT_OPTIMIZATION_LEVEL = "{opt}"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; }};'))
    target_configs.append(add('target'+mode, f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = com.yikessa.HoldTranslate; INFOPLIST_FILE = LingoWisp/Resources/Info.plist; GENERATE_INFOPLIST_FILE = NO; CODE_SIGN_IDENTITY = "-"; CODE_SIGN_STYLE = Manual; ENABLE_APP_SANDBOX = NO; ENABLE_HARDENED_RUNTIME = YES; SWIFT_EMIT_LOC_STRINGS = NO; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks"; }};'))
pl = add('projectConfigs', f'isa = XCConfigurationList; buildConfigurations = {refs(proj_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
tl = add('targetConfigs', f'isa = XCConfigurationList; buildConfigurations = {refs(target_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = add('target', f'isa = PBXNativeTarget; buildConfigurationList = {tl}; buildPhases = {refs([phase,frameworks,resources])}; buildRules = (); dependencies = (); name = LingoWisp; productName = LingoWisp; productReference = {product}; productType = "com.apple.product-type.application";')
pid = add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {pl}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (en, zh_CN, Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {refs([target])};')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {pid}; }}\n')
scheme = project/'xcshareddata/xcschemes'
scheme.mkdir(parents=True, exist_ok=True)
buildable = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="LingoWisp.app" BlueprintName="LingoWisp" ReferencedContainer="container:LingoWisp.xcodeproj"/>'
(scheme/'LingoWisp.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated', project)
