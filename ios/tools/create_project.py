#!/usr/bin/env python3
"""Generate a dependency-free Xcode project for the universal Titanium app."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
objects={}
count=0

def add(isa, **fields):
    global count
    count+=1
    key=f'{count:024X}'
    objects[key]={'isa':isa,**fields}
    return key

def ref(path, kind):
    return add('PBXFileReference',lastKnownFileType=kind,path=path,sourceTree='<group>')

swift=ref('App/Graph89App.swift','sourcecode.swift')
bridge=ref('App/Graph89-Bridging-Header.h','sourcecode.c.h')
resources=[ref('../TI89Titanium_OS.89u','file'),ref('../app/src/main/assets/portrait/ti89tclassic/skin.jpg','image.jpeg'),ref('../app/src/main/assets/portrait/ti89tclassic/buttonmask.bin','file'),ref('../app/src/main/assets/portrait/ti89tclassic/buttonloaction.location','text')]
product=add('PBXFileReference',explicitFileType='wrapper.application',path='Graph89.app',sourceTree='BUILT_PRODUCTS_DIR')
products=add('PBXGroup',children=[product],name='Products',sourceTree='<group>')
group=add('PBXGroup',children=[swift,bridge,*resources,products],sourceTree='<group>')
sourcephase=add('PBXSourcesBuildPhase',buildActionMask=2147483647,files=[add('PBXBuildFile',fileRef=swift)],runOnlyForDeploymentPostprocessing=0)
resourcephase=add('PBXResourcesBuildPhase',buildActionMask=2147483647,files=[add('PBXBuildFile',fileRef=r) for r in resources],runOnlyForDeploymentPostprocessing=0)
frameworkphase=add('PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
nativephase=add('PBXShellScriptBuildPhase',buildActionMask=2147483647,files=[],inputPaths=[],outputPaths=[],runOnlyForDeploymentPostprocessing=0,alwaysOutOfDate=1,name='Build calculator engine',shellPath='/bin/sh',shellScript='set -eu\n/usr/bin/python3 "$SRCROOT/tools/build_native.py" --sdk "$PLATFORM_NAME"\n')
settings={
 'PRODUCT_BUNDLE_IDENTIFIER':'com.codybarton.graph89.ios',
 'PRODUCT_NAME':'Graph89', 'SDKROOT':'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET':'16.0',
 'TARGETED_DEVICE_FAMILY':'1,2', 'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator',
 'ARCHS':'arm64', 'SWIFT_VERSION':'5.0', 'SWIFT_OBJC_BRIDGING_HEADER':'App/Graph89-Bridging-Header.h',
 'GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':'App/Info.plist','INFOPLIST_KEY_CFBundleDisplayName':'Graph 89',
 'INFOPLIST_KEY_LSApplicationCategoryType':'public.app-category.education',
 'INFOPLIST_KEY_UILaunchScreen_Generation':'YES',
 'INFOPLIST_KEY_UISupportedInterfaceOrientations':'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
 'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad':'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
 'CODE_SIGN_STYLE':'Automatic','ENABLE_USER_SCRIPT_SANDBOXING':'NO',
 'OTHER_LDFLAGS':['$(inherited)','$(SRCROOT)/build/$(PLATFORM_NAME)/libGraph89.a','-lz','-liconv'],
 'CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'0.1.0',
}
configs=[add('XCBuildConfiguration',name=name,buildSettings={**settings,'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name=='Debug' else '-O'}) for name in ['Debug','Release']]
configlist=add('XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
target=add('PBXNativeTarget',buildConfigurationList=configlist,buildPhases=[nativephase,sourcephase,frameworkphase,resourcephase],buildRules=[],dependencies=[],name='Graph89',productName='Graph89',productReference=product,productType='com.apple.product-type.application')
projectconfigs=[add('XCBuildConfiguration',name=name,buildSettings={'CLANG_ENABLE_MODULES':'YES'}) for name in ['Debug','Release']]
projectlist=add('XCConfigurationList',buildConfigurations=projectconfigs,defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
project=add('PBXProject',attributes={'LastUpgradeCheck':'2700'},buildConfigurationList=projectlist,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[target])


uiSource=ref('UITests/Graph89UITests.swift','sourcecode.swift')
expected=ref('UITests/expected-five.pgm','file')
uiProduct=add('PBXFileReference',explicitFileType='wrapper.cfbundle',path='Graph89UITests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
objects[group]['children'] += [uiSource,expected]
objects[products]['children'].append(uiProduct)
uiSources=add('PBXSourcesBuildPhase',buildActionMask=2147483647,files=[add('PBXBuildFile',fileRef=uiSource)],runOnlyForDeploymentPostprocessing=0)
uiResources=add('PBXResourcesBuildPhase',buildActionMask=2147483647,files=[add('PBXBuildFile',fileRef=expected)],runOnlyForDeploymentPostprocessing=0)
uiSettings={'PRODUCT_BUNDLE_IDENTIFIER':'com.codybarton.graph89.uitests','PRODUCT_NAME':'$(TARGET_NAME)','SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'16.0','TARGETED_DEVICE_FAMILY':'1,2','SWIFT_VERSION':'5.0','GENERATE_INFOPLIST_FILE':'YES','CODE_SIGN_STYLE':'Automatic','TEST_TARGET_NAME':'Graph89'}
uiConfigs=[add('XCBuildConfiguration',name=name,buildSettings=uiSettings) for name in ['Debug','Release']]
uiConfigList=add('XCConfigurationList',buildConfigurations=uiConfigs,defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
proxy=add('PBXContainerItemProxy',containerPortal=project,proxyType=1,remoteGlobalIDString=target,remoteInfo='Graph89')
dependency=add('PBXTargetDependency',target=target,targetProxy=proxy)
uiTarget=add('PBXNativeTarget',buildConfigurationList=uiConfigList,buildPhases=[uiSources,uiResources],buildRules=[],dependencies=[dependency],name='Graph89UITests',productName='Graph89UITests',productReference=uiProduct,productType='com.apple.product-type.bundle.ui-testing')
objects[project]['targets'].append(uiTarget)

def encode(value,indent=0):
    if isinstance(value,dict):
        return '{\n'+''.join('\t'*(indent+1)+json.dumps(k)+' = '+encode(v,indent+1)+';\n' for k,v in value.items())+'\t'*indent+'}'
    if isinstance(value,list): return '('+', '.join(encode(v,indent) for v in value)+')'
    return json.dumps(str(value))
path=ROOT/'Graph89.xcodeproj'
path.mkdir(exist_ok=True)
(path/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n')
print(path)

schemeDir=path/'xcshareddata/xcschemes'
schemeDir.mkdir(parents=True,exist_ok=True)
appRef=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Graph89.app" BlueprintName="Graph89" ReferencedContainer="container:Graph89.xcodeproj"/>'
testRef=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uiTarget}" BuildableName="Graph89UITests.xctest" BlueprintName="Graph89UITests" ReferencedContainer="container:Graph89.xcodeproj"/>'
(schemeDir/'Graph89.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{appRef}</BuildActionEntry>
<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{testRef}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{testRef}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appRef}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0">{appRef}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
