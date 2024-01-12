 Current libuv version : 1.47.0

 As of now i only tested it for windows with msvc triplet.
 Normally it should work on other platforms if i didn't made
 any errors translating the CMakeFiles.txt

 If you use it as shared lib, you must add "USING_UV_SHARED=1"
 in your define before import

 TODO/Questions :

     - Windows mingw?
     - Add the libuv tests to this build ?
     - See Solaris if
     - quid of OS390/OS400?
     - quid of QNX ?
     - No plans for cywin so no port : see https://github.com/ziglang/zig/issues/751#issuecomment-614272910
