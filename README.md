# Odin android sample

This is a personal experiment to get a [Odin](https://odin-lang.org/) project running on Android.

![Screenshot of the running app](/images/screenshot.png)

Note that I have only tested and run this on Linux. It relies on a Makefile and assume a unix environment.

> [!CAUTION]
> The PC version is likely not going to run and I might remove it later to simplify the example.

It should work just fine on MacOS and Windows as long as you setup Android Studio and you either have _GNU Make_
or you translate to a similar script.

> [!NOTE]
> It should be possible to not use Android Studio at all, but it would complicate things a bit.

## Prerequisites

- [Odin](https://odin-lang.org/) installed
- [Android Studio](https://developer.android.com/studio) installed
- [Android NDK](https://developer.android.com/ndk) installed
- `ANDROID_NDK_HOME` and `ANDROID_HOME` environment variables set

For example, this is how they look like on my machine:
```bash
export ANDROID_HOME=$HOME/Android/Sdk
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/29.0.13846066
```

## Compile

The default target is android, so you can simply run: `make`.

## Deploy and debug

After compilation, you should have a directory `out/AndroidProject`.

![Directory structure after compilation](/images/structure.png)

Open this in Android Studio as a project and simply debug from there.

## Limitations

I have not yet managed to get breakpoints to work nor to have the debugger break on the source file on a crash.

For now I had to resort to *printf* debugging.

Any suggestion on how to get this working is welcome.

## Change and make your own

It should be relatively straightforward to use this as a starting point for your own android project in [Odin](https://odin-lang.org/).

You'll need `my_vendor` and `android_files`.

 - `my_vendor` contains bindings for android APIs. Note that these are very much incomplete and you *WILL* need to add stuff to it;
 - `android_files` contains necessary android files like `AndroidManifest.xml` and `build.gradle`. Change them to match your project.

You'll also need a makefile or a build script. You can take a look at `Makefile` for the command line options you'll need.

Finally, you can create your own entry point. Check `android_main` in `src/main.odin` for an example.

> [!NOTE]
> You should also add icon and resources to your project, but that's left as an exercise to the reader.

## Contributing

As and if I find the time, I'll like to clean up the vendor files and include more of the android API.

If you have done it and you feel like sharing, please open a PR.

## License

All the code in the project is licensed under the [Boost Software License 1.0](https://www.boost.org/LICENSE_1_0.txt).

See [LICENSE](LICENSE) for details.

