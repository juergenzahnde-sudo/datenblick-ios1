// Dependency-free, deterministic Xcode project generator. Run after adding Swift files.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const id = text => crypto.createHash('sha1').update(text).digest('hex').slice(0, 24).toUpperCase();
const q = JSON.stringify;
const objects = [];
const add = (key, content) => { objects.push(`\t\t${id(key)} = { ${content} };`); return id(key); };
const list = values => `(${values.join(', ')}${values.length ? ',' : ''})`;
const sourceFiles = folder => fs.readdirSync(path.join(root, folder)).filter(f => f.endsWith('.swift')).sort().map(f => `${folder}/${f}`);
const shared = sourceFiles('Shared');
const app = sourceFiles('App');
const widget = sourceFiles('Widgets');
const refs = new Map();
const file = (name, type) => {
  if (!refs.has(name)) refs.set(name, add(`file:${name}`, `isa = PBXFileReference; lastKnownFileType = ${type}; path = ${q(name)}; sourceTree = "<group>";`));
  return refs.get(name);
};
for (const name of [...shared, ...app, ...widget]) file(name, 'sourcecode.swift');
const assets = file('Assets.xcassets', 'folder.assetcatalog');
const privacy = file('Config/PrivacyInfo.xcprivacy', 'text.xml');
const config = file('Config/Project.xcconfig', 'text.xcconfig');
for (const name of ['App-Info.plist', 'Widget-Info.plist', 'App.entitlements', 'Widget.entitlements']) file(`Config/${name}`, 'text.plist.xml');
file('README.md', 'net.daringfireball.markdown');
const appProduct = add('appProduct', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Datenblick.app; sourceTree = BUILT_PRODUCTS_DIR;');
const widgetProduct = add('widgetProduct', 'isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = DatenblickWidget.appex; sourceTree = BUILT_PRODUCTS_DIR;');
const products = add('products', `isa = PBXGroup; name = Products; children = ${list([appProduct, widgetProduct])}; sourceTree = "<group>";`);
const group = add('mainGroup', `isa = PBXGroup; children = ${list([...refs.values(), products])}; sourceTree = "<group>";`);
const buildFile = (target, name, ref, extra = '') => add(`build:${target}:${name}`, `isa = PBXBuildFile; fileRef = ${ref}; ${extra}`);
const phase = (target, name, isa, files, extra = '') => add(`${target}:${name}`, `isa = ${isa}; buildActionMask = 2147483647; files = ${list(files)}; runOnlyForDeploymentPostprocessing = 0; ${extra}`);
const appSources = phase('app', 'sources', 'PBXSourcesBuildPhase', [...app, ...shared].map(n => buildFile('app', n, refs.get(n))));
const widgetSources = phase('widget', 'sources', 'PBXSourcesBuildPhase', [...widget, ...shared].map(n => buildFile('widget', n, refs.get(n))));
const appResources = phase('app', 'resources', 'PBXResourcesBuildPhase', [buildFile('app', 'assets', assets), buildFile('app', 'privacy', privacy)]);
const widgetResources = phase('widget', 'resources', 'PBXResourcesBuildPhase', [buildFile('widget', 'privacy', privacy)]);
const appFrameworks = phase('app', 'frameworks', 'PBXFrameworksBuildPhase', []);
const widgetFrameworks = phase('widget', 'frameworks', 'PBXFrameworksBuildPhase', []);
const embed = phase('app', 'embed', 'PBXCopyFilesBuildPhase', [buildFile('app', 'extension', widgetProduct, 'settings = { ATTRIBUTES = (RemoveHeadersOnCopy,); };')], 'dstPath = ""; dstSubfolderSpec = 13; name = "Embed App Extensions";');
const proxy = add('proxy', `isa = PBXContainerItemProxy; containerPortal = ${id('project')}; proxyType = 1; remoteGlobalIDString = ${id('widgetTarget')}; remoteInfo = DatenblickWidget;`);
const dependency = add('dependency', `isa = PBXTargetDependency; target = ${id('widgetTarget')}; targetProxy = ${proxy};`);
const buildSettings = (target, release) => {
  const values = {
    DEBUG_INFORMATION_FORMAT: release ? 'dwarf-with-dsym' : 'dwarf',
    SWIFT_OPTIMIZATION_LEVEL: release ? '-O' : '-Onone',
    SWIFT_COMPILATION_MODE: release ? 'wholemodule' : 'singlefile',
    SWIFT_ACTIVE_COMPILATION_CONDITIONS: release ? '' : 'DEBUG',
    PRODUCT_NAME: target === 'app' ? 'Datenblick' : 'DatenblickWidget',
    PRODUCT_BUNDLE_IDENTIFIER: target === 'app' ? '$(BASE_BUNDLE_IDENTIFIER)' : '$(BASE_BUNDLE_IDENTIFIER).widget',
    INFOPLIST_FILE: target === 'app' ? 'Config/App-Info.plist' : 'Config/Widget-Info.plist',
    CODE_SIGN_ENTITLEMENTS: target === 'app' ? 'Config/App.entitlements' : 'Config/Widget.entitlements',
    LD_RUNPATH_SEARCH_PATHS: target === 'app' ? '$(inherited) @executable_path/Frameworks' : '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks',
    ...(target === 'app' ? { ASSETCATALOG_COMPILER_APPICON_NAME: 'AppIcon', ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: 'AccentColor' } : { APPLICATION_EXTENSION_API_ONLY: 'YES', SKIP_INSTALL: 'YES' })
  };
  return Object.entries(values).map(([k, v]) => `${k} = ${q(v)};`).join(' ');
};
const configs = target => {
  const children = ['Debug', 'Release'].map(name => add(`config:${target}:${name}`, `isa = XCBuildConfiguration; baseConfigurationReference = ${config}; buildSettings = { ${target === 'project' ? '' : buildSettings(target, name === 'Release')} }; name = ${name};`));
  return add(`configs:${target}`, `isa = XCConfigurationList; buildConfigurations = ${list(children)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;`);
};
const appConfigs = configs('app');
const widgetConfigs = configs('widget');
const projectConfigs = configs('project');
add('appTarget', `isa = PBXNativeTarget; buildConfigurationList = ${appConfigs}; buildPhases = ${list([appSources, appFrameworks, appResources, embed])}; buildRules = (); dependencies = ${list([dependency])}; name = Datenblick; productName = Datenblick; productReference = ${appProduct}; productType = "com.apple.product-type.application";`);
add('widgetTarget', `isa = PBXNativeTarget; buildConfigurationList = ${widgetConfigs}; buildPhases = ${list([widgetSources, widgetFrameworks, widgetResources])}; buildRules = (); dependencies = (); name = DatenblickWidget; productName = DatenblickWidget; productReference = ${widgetProduct}; productType = "com.apple.product-type.app-extension";`);
add('project', `isa = PBXProject; attributes = { BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = { ${id('appTarget')} = { CreatedOnToolsVersion = 16.0; SystemCapabilities = { com.apple.ApplicationGroups.iOS = { enabled = 1; }; }; }; ${id('widgetTarget')} = { CreatedOnToolsVersion = 16.0; SystemCapabilities = { com.apple.ApplicationGroups.iOS = { enabled = 1; }; }; }; }; }; buildConfigurationList = ${projectConfigs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = de; hasScannedForEncodings = 0; knownRegions = (de, en, Base,); mainGroup = ${group}; productRefGroup = ${products}; projectDirPath = ""; projectRoot = ""; targets = ${list([id('appTarget'), id('widgetTarget')])};`);
const dir = path.join(root, 'Datenblick.xcodeproj');
fs.mkdirSync(path.join(dir, 'xcshareddata', 'xcschemes'), { recursive: true });
fs.writeFileSync(path.join(dir, 'project.pbxproj'), `// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n${objects.join('\n')}\n\t};\n\trootObject = ${id('project')};\n}\n`);
const buildable = `<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id('appTarget')}" BuildableName="Datenblick.app" BlueprintName="Datenblick" ReferencedContainer="container:Datenblick.xcodeproj"/>`;
fs.writeFileSync(path.join(dir, 'xcshareddata', 'xcschemes', 'Datenblick.xcscheme'), `<?xml version="1.0" encoding="UTF-8"?>\n<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">${buildable}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">${buildable}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">${buildable}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>\n`);
console.log(`Generated Xcode project: ${app.length} app, ${shared.length} shared, ${widget.length} widget Swift files.`);
