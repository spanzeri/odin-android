#+build linux:android
package android

//
// Wrap android logging functions into a logger compatible with odin context
//

import "core:log"
import "base:runtime"
import "core:fmt"
import "core:strings"

@(disabled=(ODIN_PLATFORM_SUBTARGET == .Android))
log_android_proc :: proc(data: rawptr, level: log.Level, text: string, options: log.Options, location := #caller_location) {
    options := options
    log_prio: Log_Priority
    switch level {
    case .Debug:    log_prio = .DEBUG
    case .Info:     log_prio = .INFO
    case .Warning:  log_prio = .WARN
    case .Error:    log_prio = .ERROR
    case .Fatal:    log_prio = .FATAL
    }
    log_print(
        log_prio,
        "",
        "%.*s:%d:%d: %.*s",
        len(location.file_path), raw_data(location.file_path),
        location.line, location.column,
        len(text), raw_data(text),
    );
}

create_logger :: proc() -> log.Logger {
    return log.Logger{log_android_proc, nil, log.Level.Debug, nil}
}

