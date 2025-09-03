package main

import "core:fmt"
import "core:log"
import "core:mem"
import "base:runtime"
import "my_vendor:android"
import sdl "vendor:sdl3"
import "vendor:egl"
import gl "vendor:OpenGL"

_ :: android;
_ :: sdl;
_ :: egl;

MEM_ALLOCATION_DEBUG :: ODIN_DEBUG

Engine :: struct {
    platform_poll_events_proc:  Poll_Events_Proc,
    suspended:                  bool,
    exiting:                    bool,
    android_app:                ^Android_App,
    surface:                    egl.Surface,
    window:                     rawptr,
    ctx:                        runtime.Context,
    program:                    u32,
}

Poll_Events_Proc :: #type proc (engine: ^Engine);

when ODIN_PLATFORM_SUBTARGET == .Android {

    Android_App :: android.App;

    @(export)
    android_main :: proc "c" (app: ^android.App) -> int {
        // Make sure we set a context first thing in the main function
        context = runtime.default_context();
        when ODIN_DEBUG {
            context.logger = android.create_logger();
        }

        log.info("Android main started");

        app.on_app_cmd = proc "c" (a: ^android.App, cmd: android.App_Command) {
            engine := cast(^Engine)a.user_data
            context = engine.ctx

            #partial switch cmd {
                case .INIT_WINDOW:
                    if a.window != nil {
                        engine.window = a.window
                        log.infof("Window initialized: %", engine.window)
                        render_init(engine)
                    }
                case .TERM_WINDOW:
                    engine.window = nil
                    log.info("Window terminated")
                case .GAINED_FOCUS:
                    engine.suspended = false
                case .LOST_FOCUS:
                    engine.suspended = true
            }
        }

        // @TODO: Add saved states

        engine := Engine{
            platform_poll_events_proc = proc (engine: ^Engine) {
                ident: i32
                events: i32
                source: ^android.Poll_Source

                app := engine.android_app

                // Poll all pending events.
                for {
                    if engine.exiting {
                        break
                    }

                    timeout :i32= -1 if engine.suspended else 0
                    ident := android.looper_poll_once(timeout, nil, &events, auto_cast &source)
                    if ident < 0 {
                        break
                    }

                    // Check this event.
                    if source != nil {
                        source.process(app, source)
                    }

                    // @TODO: Add sensor events. See:
                    // https://github.com/android/ndk-samples/blob/master/native-activity/app/src/main/cpp/main.cpp

                    if app.destroy_requested != 0 {
                        engine.exiting = true
                        return
                    }
                }
            },
        }

        app.user_data = &engine

        engine.android_app = app
        engine.window = app.window
        engine.ctx = context

        gl.load_up_to(4, 0, egl.gl_set_proc_address)

        common_main(&engine)

        return 0;
    }

}
else {

    // Placeholder for android.App
    Android_App :: struct {};

    main :: proc () {
        when ODIN_DEBUG {
            context.logger = log.create_console_logger(opt = { .Level, .Terminal_Color })
            defer log.destroy_console_logger(context.logger)
        }

        engine := Engine{
            platform_poll_events_proc = proc (engine: ^Engine) {
                event: sdl.Event

                // Poll all pending events.
                for sdl.PollEvent(&event) {
                    #partial switch event.type {
                    case .QUIT:
                        engine.exiting = true
                    case .WINDOW_FOCUS_LOST:
                        engine.suspended = true
                        log.info("Window focus lost, suspending")
                    case .WINDOW_FOCUS_GAINED:
                        engine.suspended = false
                        log.info("Window focus gained, resuming")
                    }
                }
            },
        }

        if (!sdl.Init({ .VIDEO })) {
            log.errorf("Failed to initialize SDL: %", sdl.GetError())
            return
        }

        defer sdl.Quit()

        window := sdl.CreateWindow(
            "Odin SDL3",
            1024, 768,
            { .RESIZABLE, .OPENGL },
        )

        gl_context := sdl.GL_CreateContext(window)
        sdl.GL_MakeCurrent(window, gl_context)

        gl.load_up_to(4, 0, sdl.gl_set_proc_address)

        engine.window = sdl.GetPointerProperty(sdl.GetWindowProperties(window), "SDL.window.native_handle", nil);
        assert(engine.window == nil, "Failed to get native window handle from SDL");
        engine.ctx = context

        render_init(&engine)

        common_main(&engine)
    }
}

common_main :: proc (engine: ^Engine) -> int {
    when MEM_ALLOCATION_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        defer mem.tracking_allocator_destroy(&track)

        context.allocator = mem.tracking_allocator(&track)

        defer report_allocation_errors(&track)
    }

    // Main loop
    for !engine.exiting {
        mem.free_all(context.temp_allocator)
        engine.platform_poll_events_proc(engine)
        if engine.window != nil {
            render_draw(engine)
            render_present(engine)
        }
    }

    return 0
}

@(disabled=!MEM_ALLOCATION_DEBUG)
report_allocation_errors :: proc (track: ^mem.Tracking_Allocator) {
    if len(track.allocation_map) > 0 {
        log.errorf("=== %v allocations not freed: ===", len(track.allocation_map))
        for _, entry in track.allocation_map {
            log.debugf("  | %v bytes @ %v", entry.size, entry.location)
        }
    }
    if len(track.bad_free_array) > 0 {
        log.errorf("=== %v incorrect frees: ===", len(track.bad_free_array))
        for entry in track.bad_free_array {
            log.debugf("  | %p @ %v", entry.memory, entry.location)
        }
    }
    assert(len(track.allocation_map) == 0, "Memory leak detected")
    assert(len(track.bad_free_array) == 0, "Incorrect memory frees detected")
}

render_init :: proc (engine: ^Engine) -> bool {
    display := egl.GetDisplay(egl.DEFAULT_DISPLAY)
    egl.Initialize(display, nil, nil)

    config: egl.Config
    num_configs: i32

    attribs := [?]i32{
        egl.SURFACE_TYPE, egl.WINDOW_BIT,
        egl.RED_SIZE, 8,
        egl.GREEN_SIZE, 8,
        egl.BLUE_SIZE, 8,
        egl.NONE,
    }

    egl.ChooseConfig(display, &attribs[0], nil, 0, &num_configs)
    assert(num_configs > 0)

    configs := make_slice([]egl.Config, num_configs, context.temp_allocator)
    egl.ChooseConfig(display, &attribs[0], raw_data(configs), num_configs, &num_configs)

    // @TODO: Pick a good one, not just the first
    config = configs[0]

    engine.surface = egl.CreateWindowSurface(display, config, auto_cast engine.window, nil)

    ctx_attribs := [?]i32{
        egl.CONTEXT_CLIENT_VERSION, 3,
        egl.NONE,
    }

    ctx := egl.CreateContext(display, config, nil, &ctx_attribs[0])
    made_curr := egl.MakeCurrent(display, engine.surface, engine.surface, ctx)
    assert(made_curr == egl.TRUE)

    render_create_simple_program(engine)

    return true;
}

clear_color := [4]f32{0.1, 0.1, 0.1, 1.0}

simple_vert_shader ::
`#version 300 es
vec3 positions[3] = vec3[](
    vec3(0.0,  0.5, 0.0),
    vec3(0.5, -0.5, 0.0),
    vec3(-0.5, -0.5, 0.0)
);
void main() {
    gl_Position = vec4(positions[gl_VertexID], 1.0);
}
`

simple_frag_shader ::
`#version 300 es
precision mediump float;
out vec4 out_color;
void main() {
    out_color = vec4(1.0, 0.0, 0.0, 1.0);
}
`

create_shader :: proc (shader_type: u32, source: cstring) -> (ok: bool, program: u32) {
    log.warnf("gl.CreateShader: %p", gl.impl_CreateShader)

    source := source
    shader := gl.CreateShader(shader_type)
    gl.ShaderSource(shader, 1, &source, nil)
    gl.CompileShader(shader)

    // Check for compilation errors
    success: i32
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, &success)
    if cast(bool)success == gl.FALSE {
        info_log := make_slice([]u8, 512, context.temp_allocator)
        gl.GetShaderInfoLog(shader, 512, nil, &info_log[0])
        log.errorf("Shader compilation failed: %", string(info_log))
        gl.DeleteShader(shader)
        return false, 0
    }
    return true, shader
}

render_create_simple_program :: proc (engine: ^Engine) {
    ok: bool
    vert_shader, frag_shader: u32
    ok, vert_shader = create_shader(gl.VERTEX_SHADER, simple_vert_shader)
    assert(ok, "Vertex shader compilation failed")
    ok,  frag_shader = create_shader(gl.FRAGMENT_SHADER, simple_frag_shader)
    assert(ok, "Fragment shader compilation failed")

    program := gl.CreateProgram()
    gl.AttachShader(program, vert_shader)
    gl.AttachShader(program, frag_shader)
    gl.LinkProgram(program)

    // Check for linking errors
    success: i32
    gl.GetProgramiv(program, gl.LINK_STATUS, &success)
    if cast(bool)success == gl.FALSE {
        info_log := make_slice([]u8, 512, context.temp_allocator)
        gl.GetProgramInfoLog(program, 512, nil, &info_log[0])
        log.errorf("Program linking failed: %", string(info_log))
        gl.DeleteProgram(program)
        return
    }

    // Clean up shaders after linking
    gl.DeleteShader(vert_shader)
    gl.DeleteShader(frag_shader)

    engine.program = program
}

render_draw :: proc (engine: ^Engine) {
    clear_color.r = 0.0 if clear_color.r > 1.0 else clear_color.r + 0.005
    clear_color.g = 0.0 if clear_color.g > 1.0 else clear_color.g + 0.003
    clear_color.b = 0.0 if clear_color.b > 1.0 else clear_color.b + 0.001
    clear_color.a = 1.0
    gl.ClearColor(clear_color.r, clear_color.g, clear_color.b, clear_color.a)
    gl.Clear(gl.COLOR_BUFFER_BIT)

    gl.UseProgram(engine.program)
    gl.DrawArrays(gl.TRIANGLES, 0, 3)
}

render_present :: proc (engine: ^Engine) {
    display := egl.GetDisplay(egl.DEFAULT_DISPLAY)
    egl.SwapBuffers(display, engine.surface)
}

