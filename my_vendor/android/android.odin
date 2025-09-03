#+build linux:android
// It would be nice to have a #+build target here, but unless I am mistaken we
// don't have one yet...

package android

import "core:c"
import "core:sys/posix"

@(ignore_duplicates)
foreign import android_lib "system:android"

@(ignore_duplicates)
foreign import log_lib "system:log"

@(default_calling_convention = "c")
foreign android_lib {
    @(link_name = "__android_log_print")
    log_print :: proc(log_level: Log_Priority, tag: cstring, fmt: cstring, #c_vararg args: ..any) ---

    @(link_name = "ALooper_pollOnce")
    looper_poll_once :: proc(timeoutMillis: i32, outFd: ^c.int, events: ^c.int, outData: ^^rawptr) -> c.int ---
}

/**
* Data associated with an ALooper fd that will be returned as the "outData"
* when that source has data ready.
*/
Poll_Source :: struct {
    // The identifier of this source.  May be LOOPER_ID_MAIN or
    // LOOPER_ID_INPUT.
    id:         i32,

    // The android_app this ident is associated with.
    app:        ^App,

    // Function to call to perform the standard processing of data from
    // this source.
    process:    #type proc "c" (app: ^App, source: ^Poll_Source) -> i32,
}

/**
* This is the interface for the standard glue code of a threaded
* application.  In this model, the application's code is running
* in its own thread separate from the main thread of the process.
* It is not required that this thread be associated with the Java
* VM, although it will need to be in order to make JNI calls any
* Java objects.
*/
App :: struct {
    // The application can place a pointer to its own state object
    // here if it likes.
    user_data:              rawptr,

    // Fill this in with the function to process main app commands (APP_CMD_*)
    on_app_cmd:             #type proc "c" (app: ^App, cmd: App_Command),

    // Fill this in with the function to process input events.  At this point
    // the event has already been pre-dispatched, and it will be finished upon
    // return.  Return 1 if you have handled the event, 0 for any default
    // dispatching.
    on_input_event:         #type proc "c" (app: ^App, event: ^Input_Event) -> i32,

    // The ANativeActivity object instance that this app is running in.
    activity:               ^Native_Activity,

    // The current configuration the app is running in.
    config:                 ^Configuration,

    // This is the last instance's saved state, as provided at creation time.
    // It is NULL if there was no state.  You can use this as you need; the
    // memory will remain around until you call android_app_exec_cmd() for
    // APP_CMD_RESUME, at which point it will be freed and savedState set to NULL.
    // These variables should only be changed when processing a APP_CMD_SAVE_STATE,
    // at which point they will be initialized to NULL and you can malloc your
    // state and place the information here.  In that case the memory will be
    // freed for you later.
    saved_state:            rawptr,
    saved_state_size:       c.size_t,

    // The ALooper associated with the app's thread.
    looper:                 ^Looper,

    // When non-NULL, this is the input queue from which the app will
    // receive user input events.
    input_queue:            ^Input_Queue,

    // When non-NULL, this is the window surface that the app can draw in.
    window:                 ^Native_Window,

    // Current content rectangle of the window; this is the area where the
    // window's content should be placed to be seen by the user.
    content_rect:           Rect,

    // Current state of the app's activity.  May be either APP_CMD_START,
    // APP_CMD_RESUME, APP_CMD_PAUSE, or APP_CMD_STOP; see below.
    activity_state:         c.int,

    // This is non-zero when the application's NativeActivity is being
    // destroyed and waiting for the app thread to complete.
    // Your android_main() must return to its caller when this is non-zero.
    destroy_requested:      c.int,

    // -------------------------------------------------
    // Below are "private" implementation of the glue code.

    mutex:                  posix.pthread_mutex_t,
    cond:                   posix.pthread_cond_t,

    msgread:                c.int,
    msgwrite:               c.int,

    thread:                 posix.pthread_t,

    cmd_poll_source:        Poll_Source,
    input_poll_source:      Poll_Source,

    running:                b32,
    state_saved:            b32,
    destroyed:              b32,
    redraw_needed:          b32,
    pending_input_queue:    ^Input_Queue,
    pending_window:         ^Native_Window,
    pending_content_rect:   Rect,
}

//
// Opaque types
//

Input_Event         :: struct {}
Native_Activity     :: struct {}
Configuration       :: struct {}
Looper              :: struct {}
Input_Queue         :: struct {}
Native_Window       :: struct {}

//
// Other types
//

Rect :: struct {
    left:   i32,
    top:    i32,
    right:  i32,
    bottom: i32,
}

App_Command :: enum c.int {
    /**
     * Command from main thread: the AInputQueue has changed.  Upon processing
     * this command, android_app->inputQueue will be updated to the new queue
     * (or NULL).
     */
    INPUT_CHANGED,

    /**
     * Command from main thread: a new ANativeWindow is ready for use.  Upon
     * receiving this command, android_app->window will contain the new window
     * surface.
     */
    INIT_WINDOW,

    /**
     * Command from main thread: the existing ANativeWindow needs to be
     * terminated.  Upon receiving this command, android_app->window still
     * contains the existing window; after calling android_app_exec_cmd
     * it will be set to NULL.
     */
    TERM_WINDOW,

    /**
     * Command from main thread: the current ANativeWindow has been resized.
     * Please redraw with its new size.
     */
    WINDOW_RESIZED,

    /**
     * Command from main thread: the system needs that the current ANativeWindow
     * be redrawn.  You should redraw the window before handing this to
     * android_app_exec_cmd() in order to avoid transient drawing glitches.
     */
    WINDOW_REDRAW_NEEDED,

    /**
     * Command from main thread: the content area of the window has changed,
     * such as from the soft input window being shown or hidden.  You can
     * find the new content rect in android_app::contentRect.
     */
    CONTENT_RECT_CHANGED,

    /**
     * Command from main thread: the app's activity window has gained
     * input focus.
     */
    GAINED_FOCUS,

    /**
     * Command from main thread: the app's activity window has lost
     * input focus.
     */
    LOST_FOCUS,

    /**
     * Command from main thread: the current device configuration has changed.
     */
    CONFIG_CHANGED,

    /**
     * Command from main thread: the system is running low on memory.
     * Try to reduce your memory use.
     */
    LOW_MEMORY,

    /**
     * Command from main thread: the app's activity has been started.
     */
    START,

    /**
     * Command from main thread: the app's activity has been resumed.
     */
    RESUME,

    /**
     * Command from main thread: the app should generate a new saved state
     * for itself, to restore from later if needed.  If you have saved state,
     * allocate it with malloc and place it in android_app.savedState with
     * the size in android_app.savedStateSize.  The will be freed for you
     * later.
     */
    SAVE_STATE,

    /**
     * Command from main thread: the app's activity has been paused.
     */
    PAUSE,

    /**
     * Command from main thread: the app's activity has been stopped.
     */
    STOP,

    /**
     * Command from main thread: the app's activity is being destroyed,
     * and waiting for the app thread to clean up and exit before proceeding.
     */
    DESTROY,
};

Log_Priority :: enum c.int {
    /** For internal use only.  */
    UNKNOWN = 0,
    /** The default priority, for internal use only.  */
    DEFAULT, /* only for SetMinPriority() */
    /** Verbose logging. Should typically be disabled for a release apk. */
    VERBOSE,
    /** Debug logging. Should typically be disabled for a release apk. */
    DEBUG,
    /** Informational logging. Should typically be disabled for a release apk. */
    INFO,
    /** Warning logging. For use with recoverable failures. */
    WARN,
    /** Error logging. For use with unrecoverable failures. */
    ERROR,
    /** Fatal logging. For use when aborting. */
    FATAL,
    /** For internal use only.  */
    SILENT, /* only for SetMinPriority(); must be last */
}
