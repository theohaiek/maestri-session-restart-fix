// Adds or removes the fix's hooks in a Claude Code settings.json on macOS without python3.
// Run with: osascript -l JavaScript msrf-settings.js <settings.json> <command> [--remove]
ObjC.import('Foundation');

function run(argv) {
    var path = argv[0];
    var command = argv[1];
    var remove = argv[2] === '--remove';
    var marker = 'msrf-record-session.sh';
    var manager = $.NSFileManager.defaultManager;
    var settings = {};
    if (manager.fileExistsAtPath(path)) {
        var text = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
        if (text && text.trim()) { settings = JSON.parse(text); }
    }
    var hooks = settings.hooks || {};
    ['UserPromptSubmit', 'SessionStart'].forEach(function (event) {
        var kept = (hooks[event] || []).filter(function (entry) {
            return !(entry.hooks || []).some(function (hook) { return String(hook.command || '').indexOf(marker) >= 0; });
        });
        if (!remove) {
            var entry = { hooks: [{ type: 'command', command: command, timeout: 15 }] };
            if (event === 'SessionStart') { entry = { matcher: 'resume|clear|compact', hooks: entry.hooks }; }
            kept.push(entry);
        }
        if (kept.length) { hooks[event] = kept; } else { delete hooks[event]; }
    });
    if (Object.keys(hooks).length) { settings.hooks = hooks; } else { delete settings.hooks; }
    var folder = $(path).stringByDeletingLastPathComponent;
    manager.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(folder, true, $(), null);
    $(JSON.stringify(settings, null, 2) + '\n').writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
}
